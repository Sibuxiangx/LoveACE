package tech.loveace.appv3.ui.screen

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Campaign
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import tech.loveace.appv3.service.ManifestPreloginNotice
import tech.loveace.appv3.service.RemoteManifestService
import tech.loveace.appv3.ui.md3e.*

/**
 * 登录前公告卡片：用于学校网络故障、强制改密等需要在登录前触达用户的场景。
 * 数据来自 manifest_v2 的 prelogin_notice 字段；拉取失败或未启用时静默隐藏，不影响登录。
 */
@Composable
fun PreloginNoticeCard(modifier: Modifier = Modifier) {
    var notice by remember { mutableStateOf<ManifestPreloginNotice?>(null) }

    LaunchedEffect(Unit) {
        notice = runCatching { RemoteManifestService.fetchManifestV2().preloginNotice }
            .getOrNull()
            ?.takeIf { it.enabled && (it.title.isNotBlank() || it.content.isNotBlank()) }
    }

    val current = notice ?: return
    val variant = when (current.level) {
        "critical" -> RibbonCardVariant.ERROR_CONTAINER
        // warning 走语义化警告容器（原先为硬编码琥珀色）
        "warning" -> RibbonCardVariant.WARNING_CONTAINER
        else -> RibbonCardVariant.PRIMARY_CONTAINER
    }
    val content = ribbonContentColor(variant)

    RibbonCard(
        modifier = modifier.fillMaxWidth(),
        variant = variant,
        radius = 28.dp,
        padding = PaddingValues(horizontal = 16.dp, vertical = 14.dp),
    ) {
        Row(verticalAlignment = Alignment.Top) {
            ShapeBadge(
                shape = RibbonShape.COOKIE_8,
                size = 32.dp,
                color = content.copy(alpha = 0.15f),
                icon = Icons.Default.Campaign,
                iconTint = content,
            )
            Spacer(Modifier.width(12.dp))
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
