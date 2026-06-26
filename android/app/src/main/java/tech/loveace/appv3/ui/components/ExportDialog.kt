package tech.loveace.appv3.ui.components

import androidx.compose.animation.*
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.FileDownload
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.DialogProperties
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

private enum class ExportState { Confirm, Exporting, Success, Failed }

/**
 * M3 Expressive 导出对话框
 *
 * 使用 BasicAlertDialog + AnimatedContent 实现状态间平滑过渡，
 * 配合 MotionScheme 动效和 Wavy 进度指示器。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExportDialog(
    title: String,
    description: String,
    onExport: suspend () -> Result<String>,
    onDismiss: () -> Unit,
) {
    var state by remember { mutableStateOf(ExportState.Confirm) }
    var resultMessage by remember { mutableStateOf("") }

    if (state == ExportState.Exporting) {
        LaunchedEffect(Unit) {
            val result = withContext(Dispatchers.IO) { onExport() }
            result.fold(
                onSuccess = { resultMessage = it; state = ExportState.Success },
                onFailure = { resultMessage = it.message ?: "未知错误"; state = ExportState.Failed },
            )
        }
    }

    BasicAlertDialog(
        onDismissRequest = { if (state != ExportState.Exporting) onDismiss() },
        properties = DialogProperties(dismissOnClickOutside = state != ExportState.Exporting),
    ) {
        Surface(
            shape = MaterialTheme.shapes.extraLarge,
            color = MaterialTheme.colorScheme.surfaceContainerHigh,
            tonalElevation = 6.dp,
        ) {
            AnimatedContent(
                targetState = state,
                transitionSpec = {
                    (fadeIn(tween(300)) +
                        scaleIn(tween(300), initialScale = 0.92f))
                        .togetherWith(
                            fadeOut(tween(150)) +
                                scaleOut(tween(150), targetScale = 0.92f)
                        ).using(SizeTransform(clip = false))
                },
                contentAlignment = Alignment.Center,
                label = "export-dialog-content",
            ) { targetState ->
                when (targetState) {
                    ExportState.Confirm -> ConfirmContent(
                        title, description,
                        onDismiss = onDismiss,
                        onConfirm = { state = ExportState.Exporting },
                    )
                    ExportState.Exporting -> ExportingContent()
                    ExportState.Success -> ResultContent(
                        isSuccess = true,
                        message = resultMessage,
                        onClose = onDismiss,
                    )
                    ExportState.Failed -> ResultContent(
                        isSuccess = false,
                        message = resultMessage,
                        onClose = onDismiss,
                    )
                }
            }
        }
    }
}


@Composable
private fun ConfirmContent(title: String, description: String, onDismiss: () -> Unit, onConfirm: () -> Unit) {
    Column(
        modifier = Modifier.padding(24.dp).widthIn(min = 280.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        // 图标容器 — 带主题色背景
        Surface(
            shape = MaterialTheme.shapes.large,
            color = MaterialTheme.colorScheme.primaryContainer,
            modifier = Modifier.size(56.dp),
        ) {
            Box(contentAlignment = Alignment.Center, modifier = Modifier.fillMaxSize()) {
                Icon(
                    Icons.Default.FileDownload, null,
                    modifier = Modifier.size(28.dp),
                    tint = MaterialTheme.colorScheme.onPrimaryContainer,
                )
            }
        }
        Text(
            title,
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center,
        )
        Text(
            description,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(4.dp))
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp, Alignment.End),
        ) {
            TextButton(onClick = onDismiss) { Text("取消") }
            Button(onClick = onConfirm, shape = MaterialTheme.shapes.large) {
                Text("导出")
            }
        }
    }
}


@Composable
private fun ExportingContent() {
    Column(
        modifier = Modifier.padding(32.dp).widthIn(min = 280.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        AppCircularProgressIndicator(
            modifier = Modifier.size(56.dp),
            color = MaterialTheme.colorScheme.primary,
            trackColor = MaterialTheme.colorScheme.surfaceContainerHighest,
        )
        Text(
            "正在导出...",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Medium,
            color = MaterialTheme.colorScheme.onSurface,
        )
        Text(
            "请稍候",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}


@Composable
private fun ResultContent(isSuccess: Boolean, message: String, onClose: () -> Unit) {
    val containerColor = if (isSuccess)
        MaterialTheme.colorScheme.primaryContainer
    else
        MaterialTheme.colorScheme.errorContainer
    val contentColor = if (isSuccess)
        MaterialTheme.colorScheme.onPrimaryContainer
    else
        MaterialTheme.colorScheme.onErrorContainer

    Column(
        modifier = Modifier.padding(24.dp).widthIn(min = 280.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Surface(
            shape = MaterialTheme.shapes.large,
            color = containerColor,
            modifier = Modifier.size(56.dp),
        ) {
            Box(contentAlignment = Alignment.Center, modifier = Modifier.fillMaxSize()) {
                Icon(
                    if (isSuccess) Icons.Default.CheckCircle else Icons.Default.Close,
                    null,
                    modifier = Modifier.size(28.dp),
                    tint = contentColor,
                )
            }
        }
        Text(
            if (isSuccess) "导出成功" else "导出失败",
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center,
        )
        Text(
            message,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(4.dp))
        Button(
            onClick = onClose,
            shape = MaterialTheme.shapes.large,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text("关闭")
        }
    }
}
