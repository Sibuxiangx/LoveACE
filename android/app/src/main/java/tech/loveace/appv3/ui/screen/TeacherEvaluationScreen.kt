package tech.loveace.appv3.ui.screen

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import tech.loveace.appv3.data.model.TeacherEvaluationCourse
import tech.loveace.appv3.ui.components.EmptyScreen
import tech.loveace.appv3.ui.components.ErrorScreen
import tech.loveace.appv3.ui.components.LoadingScreen
import tech.loveace.appv3.ui.components.AppLinearProgressIndicator
import tech.loveace.appv3.ui.viewmodel.AuthViewModel
import tech.loveace.appv3.ui.viewmodel.TeacherEvaluationTaskState
import tech.loveace.appv3.ui.viewmodel.TeacherEvaluationTaskStatus
import tech.loveace.appv3.ui.viewmodel.TeacherEvaluationUiState
import tech.loveace.appv3.ui.viewmodel.TeacherEvaluationViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TeacherEvaluationScreen(
    authViewModel: AuthViewModel,
    onBack: (() -> Unit)? = null,
    vm: TeacherEvaluationViewModel = viewModel(),
) {
    val state by vm.uiState.collectAsStateWithLifecycle()
    var showConfirm by remember { mutableStateOf(false) }

    LaunchedEffect(authViewModel.teacherEvaluationService) {
        authViewModel.teacherEvaluationService?.let {
            vm.init(it)
            vm.load()
        }
    }

    if (showConfirm) {
        AlertDialog(
            onDismissRequest = { showConfirm = false },
            title = { Text("确认开始自动评教？") },
            text = { Text("将只对待评课程创建任务：每 6 秒启动一门，准备表单后等待 140 秒再提交。期间请保持 App 前台；已提交评价无法撤回。") },
            confirmButton = {
                Button(onClick = { showConfirm = false; vm.startBatch() }) { Text("开始") }
            },
            dismissButton = { TextButton(onClick = { showConfirm = false }) { Text("取消") } },
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("自动教师评价") },
                navigationIcon = {
                    if (onBack != null) IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "返回") }
                },
                actions = {
                    IconButton(onClick = { vm.load() }, enabled = !state.isRunning) { Icon(Icons.Default.Refresh, "刷新") }
                },
            )
        },
    ) { padding ->
        TeacherEvaluationContent(
            modifier = Modifier.fillMaxSize().padding(padding),
            state = state,
            onStart = { showConfirm = true },
            onStop = { vm.stop() },
            onRetry = { vm.load() },
        )
    }
}

@Composable
fun TeacherEvaluationContent(
    state: TeacherEvaluationUiState,
    onStart: () -> Unit,
    onStop: () -> Unit,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
) {
    when {
        state.isLoading -> LoadingScreen("正在加载评教课程...")
        state.isClosed -> EmptyScreen(state.closedMessage.ifBlank { "评价暂未开启" })
        state.error != null && state.courses.isEmpty() -> ErrorScreen(state.error ?: "加载失败", onRetry)
        else -> LazyColumn(
            modifier = modifier,
            contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 16.dp, bottom = 96.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item {
                NoticeCard(
                    isRunning = state.isRunning,
                    totalCourses = state.courses.size,
                    pendingCount = state.pendingCourses.size,
                    evaluatedCount = state.evaluatedCount,
                    taskTotal = state.tasks.size,
                    finished = state.tasks.count { it.status.isTerminal() },
                    failed = state.tasks.count { it.status == TeacherEvaluationTaskStatus.Failed },
                    onStart = onStart,
                    onStop = onStop,
                )
            }

            if (state.tasks.isNotEmpty()) {
                item {
                    SectionHeader("任务状态（${state.tasks.count { it.status.isTerminal() }} / ${state.tasks.size}）")
                }
                items(state.tasks, key = { "task_${it.course.displayId}" }) { task -> TaskCard(task) }
            }

            if (state.courses.isEmpty()) {
                item { InfoCard("暂无评教课程", "如果评教已开启，可以稍后刷新重试。") }
            } else {
                item { SectionHeader("课程列表（待评 ${state.pendingCourses.size} / 总计 ${state.courses.size}）") }
                items(state.courses, key = { it.displayId }) { course -> CourseCard(course) }
            }

            if (state.logs.isNotEmpty()) {
                item { SectionHeader("日志") }
                items(state.logs.reversed()) { log ->
                    Text(log, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

@Composable
private fun NoticeCard(
    isRunning: Boolean,
    totalCourses: Int,
    pendingCount: Int,
    evaluatedCount: Int,
    taskTotal: Int,
    finished: Int,
    failed: Int,
    onStart: () -> Unit,
    onStop: () -> Unit,
) {
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer)) {
        Column(Modifier.fillMaxWidth().padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("批量自动评教", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    Text(
                        if (isRunning) "正在执行任务，请保持 App 前台" else "仅处理待评课程，已提交评价无法撤回",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.78f),
                    )
                }
                StatusPill(if (isRunning) "运行中" else if (pendingCount == 0) "已完成" else "待开始")
            }

            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                SummaryStat("总课程", totalCourses.toString(), Modifier.weight(1f))
                SummaryStat("待评", pendingCount.toString(), Modifier.weight(1f))
                SummaryStat("已评", evaluatedCount.toString(), Modifier.weight(1f))
            }

            if (taskTotal > 0) {
                AppLinearProgressIndicator(
                    progress = { finished.toFloat() / taskTotal.coerceAtLeast(1) },
                    modifier = Modifier.fillMaxWidth().height(8.dp),
                    color = MaterialTheme.colorScheme.primary,
                    trackColor = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.16f),
                )
                Text(
                    "任务进度 $finished / $taskTotal${if (failed > 0) " · 失败 $failed" else ""}",
                    style = MaterialTheme.typography.bodySmall,
                )
            }

            Text(
                "任务每 6 秒启动一门，准备表单后等待 140 秒提交；停止只会取消未提交任务。",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.78f),
            )
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Button(onClick = onStart, enabled = !isRunning && pendingCount > 0) { Text("开始批量评教") }
                OutlinedButton(onClick = onStop, enabled = isRunning) { Text("停止") }
            }
        }
    }
}

@Composable
private fun SummaryStat(label: String, value: String, modifier: Modifier = Modifier) {
    Surface(
        modifier = modifier,
        color = MaterialTheme.colorScheme.primary.copy(alpha = 0.10f),
        shape = MaterialTheme.shapes.medium,
    ) {
        Column(Modifier.padding(horizontal = 12.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(value, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            Text(label, style = MaterialTheme.typography.labelSmall)
        }
    }
}

@Composable
private fun StatusPill(text: String) {
    Surface(color = MaterialTheme.colorScheme.primary.copy(alpha = 0.12f), shape = MaterialTheme.shapes.medium) {
        Text(
            text,
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.primary,
        )
    }
}

@Composable
private fun CourseCard(course: TeacherEvaluationCourse) {
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)) {
        Column(Modifier.fillMaxWidth().padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(course.name.ifBlank { "未命名课程" }, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.height(4.dp))
                    Text(course.teacher.ifBlank { "教师信息为空" }, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                AssistChip(onClick = {}, label = { Text(if (course.isEvaluated) "已评" else "待评") })
            }
            Spacer(Modifier.height(6.dp))
            Text(course.displayId, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun TaskCard(task: TeacherEvaluationTaskState) {
    val color = when (task.status) {
        TeacherEvaluationTaskStatus.Success -> Color(0xFF2E7D32)
        TeacherEvaluationTaskStatus.Failed -> MaterialTheme.colorScheme.error
        TeacherEvaluationTaskStatus.Cancelled -> MaterialTheme.colorScheme.outline
        else -> MaterialTheme.colorScheme.primary
    }
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)) {
        Row(Modifier.fillMaxWidth().padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(task.course.name.ifBlank { task.course.displayId }, style = MaterialTheme.typography.titleSmall)
                Text(task.course.teacher, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(task.message, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (task.status == TeacherEvaluationTaskStatus.Preparing ||
                task.status == TeacherEvaluationTaskStatus.Submitting ||
                task.status == TeacherEvaluationTaskStatus.Verifying
            ) {
                CircularProgressIndicator(modifier = Modifier.padding(end = 8.dp), strokeWidth = 2.dp)
            }
            Surface(color = color.copy(alpha = 0.12f), shape = MaterialTheme.shapes.medium) {
                Text(
                    if (task.countdownSeconds > 0) "${task.countdownSeconds}s" else task.status.label(),
                    modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
                    color = color,
                    style = MaterialTheme.typography.labelMedium,
                )
            }
        }
    }
}

@Composable
private fun InfoCard(title: String, message: String) {
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow)) {
        Column(Modifier.fillMaxWidth().padding(18.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
            Text(message, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun SectionHeader(text: String) {
    Text(text, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
}

private fun TeacherEvaluationTaskStatus.label(): String = when (this) {
    TeacherEvaluationTaskStatus.Pending -> "等待"
    TeacherEvaluationTaskStatus.Preparing -> "准备"
    TeacherEvaluationTaskStatus.Waiting -> "倒计时"
    TeacherEvaluationTaskStatus.Submitting -> "提交"
    TeacherEvaluationTaskStatus.Verifying -> "验证"
    TeacherEvaluationTaskStatus.Success -> "成功"
    TeacherEvaluationTaskStatus.Failed -> "失败"
    TeacherEvaluationTaskStatus.Cancelled -> "取消"
}

private fun TeacherEvaluationTaskStatus.isTerminal(): Boolean = when (this) {
    TeacherEvaluationTaskStatus.Success,
    TeacherEvaluationTaskStatus.Failed,
    TeacherEvaluationTaskStatus.Cancelled -> true
    TeacherEvaluationTaskStatus.Pending,
    TeacherEvaluationTaskStatus.Preparing,
    TeacherEvaluationTaskStatus.Waiting,
    TeacherEvaluationTaskStatus.Submitting,
    TeacherEvaluationTaskStatus.Verifying -> false
}
