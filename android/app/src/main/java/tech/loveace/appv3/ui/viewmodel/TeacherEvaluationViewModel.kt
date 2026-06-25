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
    val evaluationStrategy: EvaluationStrategy = EvaluationStrategy.Smart,
) {
    val pendingCourses: List<TeacherEvaluationCourse>
        get() = courses.filter { !it.isEvaluated }

    val evaluatedCount: Int
        get() = courses.count { it.isEvaluated }
}

class TeacherEvaluationViewModel : ViewModel() {
    private var service: TeacherEvaluationService? = null
    private var schedulerJob: Job? = null

    private val _uiState = MutableStateFlow(TeacherEvaluationUiState())
    val uiState: StateFlow<TeacherEvaluationUiState> = _uiState.asStateFlow()

    fun init(service: TeacherEvaluationService) {
        this.service = service
    }

    fun load() {
        val svc = service ?: return
        stop(resetRunning = false)
        viewModelScope.launch {
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
            val jobs = mutableListOf<Job>()
            try {
                pending.forEachIndexed { index, course ->
                    if (index > 0) delay(START_INTERVAL_MS)
                    jobs += launch { runTask(svc, course, pending.size, state.indexToken) }
                }
                jobs.joinAll()
                refreshAfterBatch(svc)
            } catch (_: CancellationException) {
                jobs.forEach { it.cancel() }
            } finally {
                _uiState.update { it.copy(isRunning = false) }
            }
        }
    }

    fun stop(resetRunning: Boolean = true) {
        schedulerJob?.cancel()
        schedulerJob = null
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

    fun setStrategy(strategy: EvaluationStrategy) {
        if (_uiState.value.isRunning) return
        _uiState.update { it.copy(evaluationStrategy = strategy) }
    }

    private suspend fun runTask(
        service: TeacherEvaluationService,
        course: TeacherEvaluationCourse,
        pendingCount: Int,
        indexToken: String,
    ) {
        try {
            updateTask(course, TeacherEvaluationTaskStatus.Preparing, "正在访问评价页并生成表单")
            val prepare = service.prepareEvaluation(course, pendingCount, indexToken, state.evaluationStrategy)
            val prepared = prepare.data
            if (!prepare.success || prepared == null) {
                failTask(course, prepare.error ?: "准备评价表单失败")
                return
            }

            for (second in WAIT_BEFORE_SUBMIT_SECONDS downTo 1) {
                updateTask(course, TeacherEvaluationTaskStatus.Waiting, "等待提交", second)
                delay(1000)
            }

            updateTask(course, TeacherEvaluationTaskStatus.Submitting, "正在提交评价")
            val submit = service.submitEvaluation(prepared)
            val submitResult = submit.data
            if (!submit.success || submitResult?.success != true) {
                failTask(course, submitResult?.message ?: submit.error ?: "提交评价失败")
                return
            }

            updateTask(course, TeacherEvaluationTaskStatus.Verifying, "正在刷新课程列表验证")
            val verified = service.verifyCourseEvaluated(course)
            if (verified.success && verified.data == true) {
                updateTask(course, TeacherEvaluationTaskStatus.Success, "提交成功，服务器已确认")
                addLog("${course.displayName()} 提交成功")
            } else {
                failTask(course, verified.error ?: "评教未生效，服务器未确认")
            }
        } catch (_: CancellationException) {
            updateTask(course, TeacherEvaluationTaskStatus.Cancelled, "已取消", 0)
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

    private fun failTask(course: TeacherEvaluationCourse, message: String) {
        updateTask(course, TeacherEvaluationTaskStatus.Failed, message, 0)
        addLog("${course.displayName()} 失败：$message")
    }

    private fun updateTask(
        course: TeacherEvaluationCourse,
        status: TeacherEvaluationTaskStatus,
        message: String,
        countdown: Int = 0,
    ) {
        _uiState.update { state ->
            state.copy(
                tasks = state.tasks.map { task ->
                    if (task.course.matches(course)) {
                        task.copy(status = status, message = message, countdownSeconds = countdown)
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
    }
}
