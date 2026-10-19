package tech.loveace.appv3.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.joinAll
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import tech.loveace.appv3.data.model.TeacherEvaluationCourse
import tech.loveace.appv3.data.service.TeacherEvaluationService

enum class TeacherEvaluationTaskStatus { Pending, Preparing, Waiting, Submitting, Verifying, Success, Failed, Cancelled }

data class TeacherEvaluationTaskState(
    val course: TeacherEvaluationCourse,
    val status: TeacherEvaluationTaskStatus = TeacherEvaluationTaskStatus.Pending,
    val message: String = "等待开始",
    val countdownSeconds: Int = 0,
    /** 轻量错误分类：prepareFailed / submitFailed / verifyMismatch / unknown */
    val errorKind: String = "",
)

data class TeacherEvaluationUiState(
    val isLoading: Boolean = false,
    val isRunning: Boolean = false,
    val isClosed: Boolean = false,
    val closedMessage: String = "",
    val indexToken: String = "",
    val courses: List<TeacherEvaluationCourse> = emptyList(),
    val tasks: List<TeacherEvaluationTaskState> = emptyList(),
    val logs: List<String> = emptyList(),
    val error: String? = null,
    /** 首次访问保护倒计时（秒），0 表示未处于保护等待 */
    val protectionWaitSeconds: Int = 0,
    val protectionWaitTotalSeconds: Int = 0,
) {
    val pendingCourses: List<TeacherEvaluationCourse>
        get() = courses.filter { !it.isEvaluated }

    val evaluatedCount: Int
        get() = courses.count { it.isEvaluated }
}

class TeacherEvaluationViewModel : ViewModel() {
    private var service: TeacherEvaluationService? = null
    private var schedulerJob: Job? = null
    private var loaderJob: Job? = null
    private var protectionAttempt = 0

    private val _uiState = MutableStateFlow(TeacherEvaluationUiState())
    val uiState: StateFlow<TeacherEvaluationUiState> = _uiState.asStateFlow()

    fun init(service: TeacherEvaluationService) {
        this.service = service
    }

    fun load() {
        val svc = service ?: return
        stop(resetRunning = false)
        loaderJob = viewModelScope.launch {
            _uiState.update {
                it.copy(
                    isLoading = true,
                    isRunning = false,
                    isClosed = false,
                    closedMessage = "",
                    error = null,
                    tasks = emptyList(),
                )
            }
            val result = svc.loadCourses()
            val data = result.data
            if (!result.success || data == null) {
                val error = result.error ?: "获取评教课程失败"
                _uiState.update { it.copy(isLoading = false, error = error) }
                addLog(error)
                return@launch
            }
            if (data.isClosed) {
                _uiState.update {
                    it.copy(
                        isLoading = false,
                        isClosed = true,
                        closedMessage = data.closedMessage.ifBlank { "评价暂未开启" },
                        indexToken = data.tokenValue,
                        courses = emptyList(),
                        tasks = emptyList(),
                    )
                }
                addLog("评价暂未开启")
                return@launch
            }
            if (data.protection.requiresInitialWait) {
                // 首次访问保护：显示倒计时，等待后重新拉取 index / 课程列表
                if (protectionAttempt >= MAX_PROTECTION_WAITS) {
                    _uiState.update {
                        it.copy(isLoading = false, protectionWaitSeconds = 0, protectionWaitTotalSeconds = 0, error = "首次访问保护未解除，请稍后手动刷新重试")
                    }
                    addLog("首次访问保护未解除，已停止自动重试")
                    return@launch
                }
                protectionAttempt++
                val waitSeconds = data.protection.waitSeconds
                _uiState.update {
                    it.copy(
                        isLoading = false,
                        indexToken = data.tokenValue,
                        courses = emptyList(),
                        tasks = emptyList(),
                        protectionWaitTotalSeconds = waitSeconds,
                        protectionWaitSeconds = waitSeconds,
                    )
                }
                addLog("首次评教需阅读须知，等待 $waitSeconds 秒后继续")
                for (second in waitSeconds downTo 1) {
                    _uiState.update { it.copy(protectionWaitSeconds = second) }
                    delay(1000)
                }
                _uiState.update { it.copy(protectionWaitSeconds = 0, protectionWaitTotalSeconds = 0) }
                addLog("保护等待结束，重新加载评教页")
                load()
                return@launch
            }
            protectionAttempt = 0
            _uiState.update {
                it.copy(
                    isLoading = false,
                    protectionWaitSeconds = 0,
                    protectionWaitTotalSeconds = 0,
                    indexToken = data.tokenValue,
                    courses = data.courses,
                    tasks = emptyList(),
                    error = null,
                )
            }
            addLog("已加载 ${data.courses.size} 门课程，待评 ${data.courses.count { !it.isEvaluated }} 门")
        }
    }

    fun startBatch() {
        val svc = service ?: return
        val state = _uiState.value
        val pending = state.pendingCourses
        if (state.isRunning || pending.isEmpty() || state.indexToken.isBlank()) return

        stop(resetRunning = false)
        _uiState.update {
            it.copy(
                isRunning = true,
                tasks = pending.map { course -> TeacherEvaluationTaskState(course = course) },
                error = null,
            )
        }
        addLog("批量评教已启动，请保持 App 前台；已提交评价无法撤回")

        schedulerJob = viewModelScope.launch {
            try {
                runRound(svc, pending, state.indexToken)
                if (!isActive) return@launch

                // 批后补偿：刷新列表，对失败且仍未评的课程补跑一轮
                var retryCourses = collectRetryCourses()
                if (retryCourses.isNotEmpty()) {
                    addLog("批后补偿：${retryCourses.size} 门课程将自动重试一轮")
                    refreshAfterBatch(svc)
                    retryCourses = collectRetryCourses()
                    if (retryCourses.isNotEmpty()) {
                        runRound(svc, retryCourses, _uiState.value.indexToken)
                        if (isActive) refreshAfterBatch(svc)
                    } else {
                        addLog("批后补偿：失败课程刷新后均已确认已评，无需重试")
                    }
                }
            } catch (_: CancellationException) {
            } finally {
                _uiState.update { it.copy(isRunning = false) }
            }
        }
    }

    /** 按标准间隔启动一轮任务并等待全部完成（取消通过 delay/joinAll 的取消传播实现） */
    private suspend fun runRound(
        service: TeacherEvaluationService,
        courses: List<TeacherEvaluationCourse>,
        indexToken: String,
    ) {
        val jobs = mutableListOf<Job>()
        courses.forEachIndexed { index, course ->
            if (index > 0) delay(START_INTERVAL_MS)
            jobs += launch { runTask(service, course, courses.size, indexToken) }
        }
        jobs.joinAll()
    }

    /** 收集失败课程，剔除刷新后已确认已评的，并把剩余任务重置为待重试 */
    private fun collectRetryCourses(): List<TeacherEvaluationCourse> {
        val refreshed = _uiState.value.courses
        val retryCourses = _uiState.value.tasks
            .filter { it.status == TeacherEvaluationTaskStatus.Failed }
            .map { it.course }
            .filter { course -> refreshed.firstOrNull { it.matches(course) }?.isEvaluated != true }
        if (retryCourses.isNotEmpty()) {
            _uiState.update { state ->
                state.copy(
                    tasks = state.tasks.map { task ->
                        if (task.status == TeacherEvaluationTaskStatus.Failed &&
                            retryCourses.any { it.matches(task.course) }
                        ) {
                            task.copy(status = TeacherEvaluationTaskStatus.Pending, message = "批后重试等待中", errorKind = "")
                        } else task
                    },
                )
            }
        }
        return retryCourses
    }

    fun stop(resetRunning: Boolean = true) {
        schedulerJob?.cancel()
        schedulerJob = null
        loaderJob?.cancel()
        loaderJob = null
        if (resetRunning) {
            _uiState.update { state ->
                state.copy(
                    isRunning = false,
                    protectionWaitSeconds = 0,
                    protectionWaitTotalSeconds = 0,
                    tasks = state.tasks.map { task ->
                        if (task.status.isActive()) {
                            task.copy(status = TeacherEvaluationTaskStatus.Cancelled, message = "已停止", countdownSeconds = 0)
                        } else task
                    },
                )
            }
            addLog("批量评教已停止；已提交的评价不会撤回")
        }
    }

    private suspend fun runTask(
        service: TeacherEvaluationService,
        course: TeacherEvaluationCourse,
        pendingCount: Int,
        indexToken: String,
    ) {
        try {
            updateTask(course, TeacherEvaluationTaskStatus.Preparing, "正在访问评价页并生成表单")
            var prepare = service.prepareEvaluation(course, pendingCount, indexToken)
            if ((!prepare.success || prepare.data == null) && prepare.retryable) {
                // 瞬时失败（网络抖动/HTTP 5xx）立即重试一次
                addLog("${course.displayName()} 准备失败，立即重试一次")
                updateTask(course, TeacherEvaluationTaskStatus.Preparing, "准备失败，立即重试")
                prepare = service.prepareEvaluation(course, pendingCount, indexToken)
            }
            val prepared = prepare.data
            if (!prepare.success || prepared == null) {
                failTask(course, prepare.error ?: "准备评价表单失败", "prepareFailed")
                return
            }

            awaitSubmitWait(course, "等待提交")

            updateTask(course, TeacherEvaluationTaskStatus.Submitting, "正在提交评价")
            val submit = service.submitEvaluation(prepared)
            val submitResult = submit.data
            if (!submit.success || submitResult?.success != true) {
                // 验证兜底：submit 响应异常但服务器实际已记录时按成功处理
                updateTask(course, TeacherEvaluationTaskStatus.Verifying, "提交响应异常，正在核实")
                val fallback = service.verifyCourseEvaluated(course)
                if (fallback.success && fallback.data == true) {
                    updateTask(course, TeacherEvaluationTaskStatus.Success, "提交成功（响应异常，服务器已确认）")
                    addLog("${course.displayName()} 提交成功（响应异常，已核实）")
                    return
                }
                // 立即重试一次完整流程：刷新 index token → 重新 prepare（不复用旧评价页 token）→ 等待 → 提交
                addLog("${course.displayName()} 提交失败，刷新 token 后重试一次")
                updateTask(course, TeacherEvaluationTaskStatus.Preparing, "提交失败，重新准备表单")
                val refreshedToken = service.fetchIndexToken()
                val retryPrepare = service.prepareEvaluation(
                    course, pendingCount, refreshedToken.data?.takeIf { it.isNotBlank() } ?: indexToken,
                )
                val retryPrepared = retryPrepare.data
                if (!retryPrepare.success || retryPrepared == null) {
                    failTask(course, retryPrepare.error ?: "重试准备评价表单失败", "submitFailed")
                    return
                }

                awaitSubmitWait(course, "重试等待提交")

                updateTask(course, TeacherEvaluationTaskStatus.Submitting, "正在重新提交评价")
                val retrySubmit = service.submitEvaluation(retryPrepared)
                val retrySubmitResult = retrySubmit.data
                if (!retrySubmit.success || retrySubmitResult?.success != true) {
                    failTask(course, retrySubmitResult?.message ?: retrySubmit.error ?: "提交评价失败", "submitFailed")
                    return
                }
            }

            updateTask(course, TeacherEvaluationTaskStatus.Verifying, "正在刷新课程列表验证")
            val verified = service.verifyCourseEvaluated(course)
            if (verified.success && verified.data == true) {
                updateTask(course, TeacherEvaluationTaskStatus.Success, "提交成功，服务器已确认")
                addLog("${course.displayName()} 提交成功")
            } else {
                failTask(course, verified.error ?: "评教未生效，服务器未确认", "verifyMismatch")
            }
        } catch (_: CancellationException) {
            updateTask(course, TeacherEvaluationTaskStatus.Cancelled, "已取消", 0)
        }
    }

    /** 单门评价页提交前等待：防止评价页 token 生成后过快提交 */
    private suspend fun awaitSubmitWait(course: TeacherEvaluationCourse, label: String) {
        for (second in WAIT_BEFORE_SUBMIT_SECONDS downTo 1) {
            updateTask(course, TeacherEvaluationTaskStatus.Waiting, label, second)
            delay(1000)
        }
    }

    private suspend fun refreshAfterBatch(service: TeacherEvaluationService) {
        val result = service.loadCourses()
        val data = result.data
        if (result.success && data != null && !data.isClosed) {
            _uiState.update { it.copy(courses = data.courses, indexToken = data.tokenValue) }
            addLog("批量任务结束，已刷新课程列表")
        } else if (result.error != null) {
            addLog("批量任务结束后刷新失败：${result.error}")
        }
    }

    private fun failTask(course: TeacherEvaluationCourse, message: String, errorKind: String = "unknown") {
        updateTask(course, TeacherEvaluationTaskStatus.Failed, message, 0, errorKind)
        addLog("${course.displayName()} 失败[$errorKind]：$message")
    }

    private fun updateTask(
        course: TeacherEvaluationCourse,
        status: TeacherEvaluationTaskStatus,
        message: String,
        countdown: Int = 0,
        errorKind: String? = null,
    ) {
        _uiState.update { state ->
            state.copy(
                tasks = state.tasks.map { task ->
                    if (task.course.matches(course)) {
                        task.copy(
                            status = status,
                            message = message,
                            countdownSeconds = countdown,
                            errorKind = errorKind ?: task.errorKind,
                        )
                    } else task
                }
            )
        }
    }

    private fun addLog(message: String) {
        _uiState.update { it.copy(logs = (it.logs + message).takeLast(80)) }
    }

    override fun onCleared() {
        stop(resetRunning = false)
        super.onCleared()
    }

    private fun TeacherEvaluationTaskStatus.isActive(): Boolean = when (this) {
        TeacherEvaluationTaskStatus.Pending,
        TeacherEvaluationTaskStatus.Preparing,
        TeacherEvaluationTaskStatus.Waiting,
        TeacherEvaluationTaskStatus.Submitting,
        TeacherEvaluationTaskStatus.Verifying -> true
        TeacherEvaluationTaskStatus.Success,
        TeacherEvaluationTaskStatus.Failed,
        TeacherEvaluationTaskStatus.Cancelled -> false
    }

    private fun TeacherEvaluationCourse.displayName(): String = listOf(name, teacher)
        .filter { it.isNotBlank() }
        .joinToString(" / ")
        .ifBlank { displayId }

    companion object {
        private const val START_INTERVAL_MS = 6_000L
        private const val WAIT_BEFORE_SUBMIT_SECONDS = 140

        /** 首次访问保护：最多自动等待重载次数（超过则要求手动刷新） */
        private const val MAX_PROTECTION_WAITS = 2
    }
}
