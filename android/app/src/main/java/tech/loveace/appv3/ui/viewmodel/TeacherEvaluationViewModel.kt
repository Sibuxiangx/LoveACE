package tech.loveace.appv3.ui.viewmodel

import android.app.Application
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.joinAll
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import tech.loveace.appv3.data.model.TeacherEvaluationCourse
import tech.loveace.appv3.data.service.TeacherEvaluationService
import tech.loveace.appv3.data.model.TeacherEvaluationPreparedForm
import tech.loveace.appv3.data.model.TeacherEvaluationScoreMode
import tech.loveace.appv3.data.model.UniResponse

enum class TeacherEvaluationTaskStatus { Pending, Preparing, Waiting, Submitting, Verifying, Success, Failed, Cancelled }

data class TeacherEvaluationTaskState(
    val course: TeacherEvaluationCourse,
    val status: TeacherEvaluationTaskStatus = TeacherEvaluationTaskStatus.Pending,
    val message: String = "等待开始",
    val countdownSeconds: Int = 0,
    /** 轻量错误分类：prepareFailed / submitFailed / verifyMismatch / verifyUnknown / unknown */
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
    val scoreMode: TeacherEvaluationScoreMode = TeacherEvaluationScoreMode.Random,
) {
    val pendingCourses: List<TeacherEvaluationCourse>
        get() = courses.filter { !it.isEvaluated }

    val evaluatedCount: Int
        get() = courses.count { it.isEvaluated }
}

class TeacherEvaluationViewModel(application: Application) : AndroidViewModel(application) {
    private var service: TeacherEvaluationService? = null
    private var schedulerJob: Job? = null
    private var loaderJob: Job? = null

    private val prefs = application.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private val _uiState = MutableStateFlow(
        TeacherEvaluationUiState(
            scoreMode = TeacherEvaluationScoreMode.fromStored(prefs.getString(KEY_SCORE_MODE, null)),
        ),
    )
    val uiState: StateFlow<TeacherEvaluationUiState> = _uiState.asStateFlow()

    fun init(service: TeacherEvaluationService) {
        this.service = service
    }

    /** 切换评分模式并持久化；批量评教进行中不可修改（批次在开始时读取一次） */
    fun setScoreMode(mode: TeacherEvaluationScoreMode) {
        if (_uiState.value.isRunning) return
        prefs.edit().putString(KEY_SCORE_MODE, mode.stored).apply()
        _uiState.update { it.copy(scoreMode = mode) }
    }

    private fun currentService(): TeacherEvaluationService =
        service ?: throw CancellationException("评教服务未就绪")

    /** 每次准备表单前重新获取首页 token，不复用批次开始时的快照（快照会随时间失效） */
    private suspend fun prepareWithFreshToken(
        course: TeacherEvaluationCourse,
        pendingCount: Int,
        scoreMode: TeacherEvaluationScoreMode,
    ): UniResponse<TeacherEvaluationPreparedForm> {
        val svc = currentService()
        val index = svc.fetchIndexToken()
        val token = index.data?.takeIf { index.success && it.isNotBlank() }
            ?: return UniResponse.failure(index.error ?: "未找到评价页入口 token", retryable = true)
        return svc.prepareEvaluation(course, pendingCount, token, scoreMode)
    }

    fun load() {
        // 批量评教进行中时不重新加载：会话重连会换 service 实例，批次通过 currentService() 继续使用新实例
        if (_uiState.value.isRunning) return
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
            _uiState.update {
                it.copy(
                    isLoading = false,
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
        if (service == null) return
        val state = _uiState.value
        val pending = state.pendingCourses
        val scoreMode = state.scoreMode
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
                runRound(pending, scoreMode)
                if (!isActive) return@launch

                // 批后补偿：先刷新列表，再只对"准备失败/提交失败"且服务器确认未评的课程补跑一轮；刷新失败则不补偿
                val hasRetryable = _uiState.value.tasks.any {
                    it.status == TeacherEvaluationTaskStatus.Failed && it.errorKind in RETRYABLE_KINDS
                }
                if (hasRetryable) {
                    if (!refreshAfterBatch()) return@launch
                    val retryCourses = collectRetryCourses()
                    if (retryCourses.isNotEmpty()) {
                        addLog("批后补偿：${retryCourses.size} 门课程将自动重试一轮")
                        runRound(retryCourses, scoreMode)
                        if (isActive) refreshAfterBatch()
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
        courses: List<TeacherEvaluationCourse>,
        scoreMode: TeacherEvaluationScoreMode,
    ) {
        coroutineScope {
            val jobs = mutableListOf<Job>()
            courses.forEachIndexed { index, course ->
                if (index > 0) delay(START_INTERVAL_MS)
                jobs += launch { runTask(course, courses.size, scoreMode) }
            }
            jobs.joinAll()
        }
    }

    /** 收集失败课程，剔除刷新后已确认已评的，并把剩余任务重置为待重试 */
    private fun collectRetryCourses(): List<TeacherEvaluationCourse> {
        val refreshed = _uiState.value.courses
        val retryCourses = _uiState.value.tasks
            .filter { it.status == TeacherEvaluationTaskStatus.Failed && it.errorKind in RETRYABLE_KINDS }
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
        course: TeacherEvaluationCourse,
        pendingCount: Int,
        scoreMode: TeacherEvaluationScoreMode,
    ) {
        try {
            updateTask(course, TeacherEvaluationTaskStatus.Preparing, "正在访问评价页并生成表单")
            var prepare = prepareWithFreshToken(course, pendingCount, scoreMode)
            if ((!prepare.success || prepare.data == null) && prepare.retryable) {
                // 瞬时失败（网络抖动、评价页未返回 token）：重新获取 token 后立即重试一次
                addLog("${course.displayName()} 准备失败，重新获取 token 后重试一次")
                updateTask(course, TeacherEvaluationTaskStatus.Preparing, "准备失败，重新获取后重试")
                prepare = prepareWithFreshToken(course, pendingCount, scoreMode)
            }
            val prepared = prepare.data
            if (!prepare.success || prepared == null) {
                failTask(course, prepare.error ?: "准备评价表单失败", "prepareFailed")
                return
            }

            awaitSubmitWait(course, "等待提交")

            updateTask(course, TeacherEvaluationTaskStatus.Submitting, "正在提交评价")
            val submit = currentService().submitEvaluation(prepared)
            val submitResult = submit.data
            if (submit.success && submitResult?.success == true) {
                confirmAfterSubmit(course)
                return
            }

            // 提交结果不确定：先核实；核实本身失败时绝不重新提交，避免重复提交
            updateTask(course, TeacherEvaluationTaskStatus.Verifying, "提交结果不确定，正在核实")
            val firstCheck = currentService().verifyCourseEvaluated(course)
            if (!firstCheck.success) {
                failTask(course, "提交结果无法核实，未重新提交，请稍后刷新查看", "verifyUnknown")
                return
            }
            if (firstCheck.data == true) {
                updateTask(course, TeacherEvaluationTaskStatus.Success, "提交成功（响应异常，服务器已确认）")
                addLog("${course.displayName()} 提交成功（响应异常，已核实）")
                return
            }

            // 服务器确认未记录：重新准备表单并提交一次
            addLog("${course.displayName()} 提交未生效，重新准备后提交一次")
            updateTask(course, TeacherEvaluationTaskStatus.Preparing, "提交未生效，重新准备表单")
            val retryPrepare = prepareWithFreshToken(course, pendingCount, scoreMode)
            val retryPrepared = retryPrepare.data
            if (!retryPrepare.success || retryPrepared == null) {
                failTask(course, retryPrepare.error ?: "重试准备评价表单失败", "submitFailed")
                return
            }

            awaitSubmitWait(course, "重试等待提交")

            updateTask(course, TeacherEvaluationTaskStatus.Submitting, "正在重新提交评价")
            val retrySubmit = currentService().submitEvaluation(retryPrepared)
            val retrySubmitResult = retrySubmit.data
            if (retrySubmit.success && retrySubmitResult?.success == true) {
                confirmAfterSubmit(course)
                return
            }

            // 第二次提交仍不确定：只再核实一次，不再提交
            updateTask(course, TeacherEvaluationTaskStatus.Verifying, "再次核实提交结果")
            val secondCheck = currentService().verifyCourseEvaluated(course)
            when {
                !secondCheck.success -> failTask(course, "提交结果无法核实，未再次提交，请稍后刷新查看", "verifyUnknown")
                secondCheck.data == true -> {
                    updateTask(course, TeacherEvaluationTaskStatus.Success, "提交成功，服务器已确认")
                    addLog("${course.displayName()} 提交成功（已核实）")
                }
                else -> failTask(course, retrySubmitResult?.message ?: retrySubmit.error ?: "提交评价失败", "submitFailed")
            }
        } catch (_: CancellationException) {
            updateTask(course, TeacherEvaluationTaskStatus.Cancelled, "已取消", 0)
        }
    }

    /** 提交返回成功后核实列表；核实出错只标记为需要核实，不当作未提交而重提 */
    private suspend fun confirmAfterSubmit(course: TeacherEvaluationCourse) {
        updateTask(course, TeacherEvaluationTaskStatus.Verifying, "正在刷新课程列表验证")
        val verified = currentService().verifyCourseEvaluated(course)
        when {
            !verified.success -> failTask(course, "提交已返回成功，但刷新列表失败，请稍后刷新查看", "verifyUnknown")
            verified.data == true -> {
                updateTask(course, TeacherEvaluationTaskStatus.Success, "提交成功，服务器已确认")
                addLog("${course.displayName()} 提交成功")
            }
            else -> failTask(course, "评教未生效，服务器未确认", "verifyMismatch")
        }
    }

    /** 单门评价页提交前等待：防止评价页 token 生成后过快提交 */
    private suspend fun awaitSubmitWait(course: TeacherEvaluationCourse, label: String) {
        for (second in WAIT_BEFORE_SUBMIT_SECONDS downTo 1) {
            updateTask(course, TeacherEvaluationTaskStatus.Waiting, label, second)
            delay(1000)
        }
    }

    /** 批量结束后刷新课程列表；返回是否成功，失败时不做批后补偿 */
    private suspend fun refreshAfterBatch(): Boolean {
        val result = currentService().loadCourses()
        val data = result.data
        if (result.success && data != null && !data.isClosed) {
            _uiState.update { it.copy(courses = data.courses, indexToken = data.tokenValue) }
            addLog("批量任务结束，已刷新课程列表")
            return true
        }
        addLog("批量任务结束后刷新失败：${result.error ?: "评价已关闭"}")
        return false
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
        private const val PREFS_NAME = "teacher_evaluation"
        private const val KEY_SCORE_MODE = "teacher_eval_score_mode"
        private const val START_INTERVAL_MS = 6_000L
        private const val WAIT_BEFORE_SUBMIT_SECONDS = 140

        /** 只有这两类失败会进入批后补偿；verifyUnknown 绝不自动重新提交 */
        private val RETRYABLE_KINDS = setOf("prepareFailed", "submitFailed")
    }
}
