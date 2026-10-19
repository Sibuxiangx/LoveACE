package tech.loveace.appv3.ui.screen

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import tech.loveace.appv3.service.ManifestPreloginNotice
import tech.loveace.appv3.service.RemoteManifestService

/**
 * 登录前公告横幅：用于学校网络故障、强制改密等需要在登录前触达用户的场景。
 * 数据来自 manifest_v2 的 prelogin_notice 字段；拉取失败或未启用时静默隐藏，不影响登录。
 */
@Composable
fun PreloginNoticeBanner(modifier: Modifier = Modifier) {
    var notice by remember { mutableStateOf<ManifestPreloginNotice?>(null) }

    LaunchedEffect(Unit) {
        notice = runCatching { RemoteManifestService.fetchManifestV2().preloginNotice }
            .getOrNull()
            ?.takeIf { it.enabled && (it.title.isNotBlank() || it.content.isNotBlank()) }
    }

    val current = notice ?: return
    val (container, content) = when (current.level) {
        "critical" ->
            MaterialTheme.colorScheme.errorContainer to MaterialTheme.colorScheme.onErrorContainer
        // 无主题映射的琥珀色警告容器
        "warning" -> Color(0xFFFFF3E0) to Color(0xFF8A5300)
        else ->
            MaterialTheme.colorScheme.surfaceVariant to MaterialTheme.colorScheme.onSurfaceVariant
    }

    Surface(modifier = modifier.fillMaxWidth(), color = container) {
        Row(
            Modifier.padding(horizontal = 20.dp, vertical = 10.dp),
            verticalAlignment = Alignment.Top,
        ) {
            Icon(Icons.Default.Warning, null, tint = content, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(10.dp))
            Column {
                if (current.title.isNotBlank()) {
                    Text(
                        current.title,
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.Bold,
                        color = content,
                    )
                }
                if (current.content.isNotBlank()) {
                    Text(current.content, style = MaterialTheme.typography.bodySmall, color = content)
                }
            }
        }
    }
}
