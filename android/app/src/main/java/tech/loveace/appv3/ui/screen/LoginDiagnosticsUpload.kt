package tech.loveace.appv3.ui.screen

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import tech.loveace.appv3.diagnostics.DiagnosticsUploadState
import tech.loveace.appv3.diagnostics.DiagnosticsUploadSuccess
import tech.loveace.appv3.service.QqGroupManifest
import tech.loveace.appv3.service.QqGroupService
import tech.loveace.appv3.ui.components.AppCircularProgressIndicator
import tech.loveace.appv3.ui.components.QqGroupPopup

/**
 * 登录页「分享登录诊断」区域（错误提示下方）：
 * 胶囊按钮 → 同意弹窗（显示真实的登录次数 N）→ 上传（按钮加载态）→ 失败时页面内报错 / 成功时结果页。
 */
@Composable
internal fun LoginDiagnosticsUploadSection(
    state: DiagnosticsUploadState,
    attemptCount: () -> Int,
    onUpload: () -> Unit,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var showConsent by remember { mutableStateOf(false) }
    var consentCount by remember { mutableIntStateOf(0) }
    val uploading = state is DiagnosticsUploadState.Uploading

    Column(modifier = modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        TextButton(
            onClick = {
                consentCount = attemptCount()
                showConsent = true
            },
            enabled = !uploading,
        ) {
            if (uploading) {
                AppCircularProgressIndicator(
                    modifier = Modifier.size(14.dp),
                    color = MaterialTheme.colorScheme.primary,
                )
                Spacer(Modifier.width(8.dp))
                Text("上传中…")
            } else {
                Icon(Icons.Default.Share, null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(6.dp))
                Text("分享登录诊断")
            }
        }
        if (state is DiagnosticsUploadState.Failed) {
            Spacer(Modifier.height(8.dp))
            Text(
                uploadErrorMessage(state.code),
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall,
            )
        }
    }

    if (showConsent) {
        AlertDialog(
            onDismissRequest = { showConsent = false },
            title = { Text("上传登录诊断") },
            text = {
                Text("将上传最近 $consentCount 次登录的脱敏诊断（学号部分隐藏，密码、Cookie、令牌等已替换为占位符）。链接 3 天后失效。是否继续？")
            },
            confirmButton = {
                TextButton(onClick = {
                    showConsent = false
                    onUpload()
                }) { Text("上传") }
            },
            dismissButton = {
                TextButton(onClick = { showConsent = false }) { Text("取消") }
            },
        )
    }

    if (state is DiagnosticsUploadState.Done) {
        DiagnosticsUploadResultSheet(result = state.result, onDismiss = onDismiss)
    }
}

/** 上传成功后的结果页：可选中的链接、复制链接、加入用户群（群号来自 [QqGroupService]，与登录页入口同一数据） */
@Composable
private fun DiagnosticsUploadResultSheet(result: DiagnosticsUploadSuccess, onDismiss: () -> Unit) {
    val clipboard = LocalClipboardManager.current
    var copied by remember { mutableStateOf(false) }
    var manifest by remember { mutableStateOf<QqGroupManifest?>(null) }
    var showGroup by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) { manifest = QqGroupService.fetch() }
    LaunchedEffect(copied) {
        if (copied) {
            delay(2_000L)
            copied = false
        }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
    ) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text("诊断已上传", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            Text(
                "内容已脱敏，链接 3 天后失效。",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            SelectionContainer {
                Text(result.url, style = MaterialTheme.typography.bodyMedium)
            }
            Button(
                onClick = {
                    clipboard.setText(AnnotatedString(result.url))
                    copied = true
                },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Icon(if (copied) Icons.Default.Check else Icons.Default.ContentCopy, null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text("复制链接")
            }
            manifest?.let {
                Spacer(Modifier.height(4.dp))
                Text(
                    "遇到问题可以加入用户群，把链接发给开发者，定位会更快。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                OutlinedButton(onClick = { showGroup = true }, modifier = Modifier.fillMaxWidth()) {
                    Icon(Icons.Default.Groups, null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(8.dp))
                    Text("加入用户群")
                }
            }
        }
    }

    if (showGroup) {
        manifest?.let { group ->
            QqGroupPopup(manifest = group, onDismiss = { showGroup = false })
        }
    }
}

/** 上传错误码 → 页面文字（失败时在页面内显示，不静默） */
internal fun uploadErrorMessage(code: String): String = when (code) {
    "invalid_schema" -> "诊断内容格式不符，无法上传"
    "sensitive_content_detected" -> "诊断内容含有未脱敏的信息，服务器已拒绝上传"
    "invalid_signature", "expired_timestamp", "replayed_nonce", "unauthorized" ->
        "上传鉴权失败（$code），请稍后重试或更新应用"
    "payload_too_large" -> "诊断内容过大，无法上传"
    "rate_limited" -> "上传过于频繁，请稍后再试"
    "network_error" -> "网络连接失败，请检查网络后重试"
    "not_configured" -> "当前版本未配置上传服务"
    "no_attempts" -> "没有可上传的登录记录"
    "invalid_response" -> "服务器返回异常，请稍后重试"
    else -> if (code.startsWith("http_")) {
        "服务器错误（${code.removePrefix("http_")}），请稍后重试"
    } else {
        "上传失败（$code）"
    }
}
