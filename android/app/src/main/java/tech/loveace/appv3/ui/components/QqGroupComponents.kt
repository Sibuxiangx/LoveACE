package tech.loveace.appv3.ui.components

import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.painter.ColorPainter
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.text.style.TextAlign
import coil.compose.AsyncImage
import kotlinx.coroutines.delay
import tech.loveace.appv3.service.QqGroupManifest
import tech.loveace.appv3.service.QqGroupService
import tech.loveace.appv3.ui.md3e.RibbonCard
import tech.loveace.appv3.ui.md3e.RibbonCardVariant
import tech.loveace.appv3.ui.md3e.RibbonShape
import tech.loveace.appv3.ui.md3e.ShapeBadge
import tech.loveace.appv3.ui.md3e.ribbonContentColor

/**
 * 登录页 / "我的"页的交流群入口：拉取 qq_group_v1.json，失败或未启用时整体不渲染。
 */
@Composable
fun QqGroupLoginEntry(modifier: Modifier = Modifier) {
    var manifest by remember { mutableStateOf<QqGroupManifest?>(null) }
    var showPopup by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        manifest = QqGroupService.fetch()
    }

    val current = manifest ?: return
    QqGroupEntryCard(manifest = current, onClick = { showPopup = true }, modifier = modifier)
    if (showPopup) {
        QqGroupPopup(manifest = current, onDismiss = { showPopup = false })
    }
}

/** "我的"页的交流群设置行：拉取失败或未启用时不渲染。 */
@Composable
fun QqGroupSettingsRow(modifier: Modifier = Modifier) {
    var manifest by remember { mutableStateOf<QqGroupManifest?>(null) }
    var showPopup by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        manifest = QqGroupService.fetch()
    }

    val current = manifest ?: return
    Card(
        onClick = { showPopup = true },
        modifier = modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.extraLarge,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
    ) {
        Row(
            Modifier.padding(20.dp).fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Default.Groups, null, tint = MaterialTheme.colorScheme.primary)
            Spacer(Modifier.width(12.dp))
            Text("加入交流群", style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f))
            Icon(Icons.Default.ChevronRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
    if (showPopup) {
        QqGroupPopup(manifest = current, onDismiss = { showPopup = false })
    }
}

/** 登录页醒目入口卡片：全宽，强调色容器，点击打开群号与二维码弹窗。 */
@Composable
fun QqGroupEntryCard(
    manifest: QqGroupManifest,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val variant = RibbonCardVariant.SURFACE_CONTAINER
    val content = ribbonContentColor(variant)

    RibbonCard(
        modifier = modifier.fillMaxWidth(),
        variant = variant,
        radius = 28.dp,
        padding = PaddingValues(horizontal = 16.dp, vertical = 14.dp),
        interactive = true,
        onClick = onClick,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            ShapeBadge(
                shape = RibbonShape.COOKIE_8,
                size = 40.dp,
                color = MaterialTheme.colorScheme.primary.copy(alpha = 0.15f),
                icon = Icons.Default.Groups,
                iconTint = MaterialTheme.colorScheme.primary,
            )
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(
                    "加入交流群",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Bold,
                    color = content,
                )
                Text(
                    "${manifest.title} · 点击查看群号与二维码",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Spacer(Modifier.width(8.dp))
            Icon(Icons.Default.ChevronRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/**
 * 交流群弹窗：居中卡片 + 半透明遮罩，可通过关闭按钮或点击遮罩关闭。
 */
@Composable
fun QqGroupPopup(
    manifest: QqGroupManifest,
    onDismiss: () -> Unit,
) {
    val clipboard = LocalClipboardManager.current
    val uriHandler = LocalUriHandler.current
    var copied by remember { mutableStateOf(false) }

    LaunchedEffect(copied) {
        if (copied) {
            delay(1500)
            copied = false
        }
    }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black.copy(alpha = 0.5f))
                .pointerInput(onDismiss) { detectTapGestures(onTap = { onDismiss() }) },
            contentAlignment = Alignment.Center,
        ) {
            Card(
                modifier = Modifier
                    .padding(24.dp)
                    .widthIn(max = 360.dp)
                    .fillMaxWidth()
                    // 吞掉卡片内的点击，避免冒泡到遮罩导致误关闭
                    .pointerInput(Unit) { detectTapGestures(onTap = {}) },
                shape = MaterialTheme.shapes.extraLarge,
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerHigh),
            ) {
                Column(
                    Modifier.padding(24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    Text(
                        manifest.title,
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                        textAlign = TextAlign.Center,
                    )
                    AsyncImage(
                        model = manifest.qrImageUrl,
                        contentDescription = "交流群二维码",
                        modifier = Modifier
                            .fillMaxWidth()
                            .aspectRatio(1f)
                            .clip(RoundedCornerShape(20.dp)),
                        contentScale = ContentScale.Fit,
                        placeholder = ColorPainter(MaterialTheme.colorScheme.surfaceContainerHighest),
                    )
                    Row(
                        Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            "群号 ${manifest.groupNumber}",
                            style = MaterialTheme.typography.bodyLarge,
                            modifier = Modifier.weight(1f),
                        )
                        TextButton(onClick = {
                            clipboard.setText(AnnotatedString(manifest.groupNumber))
                            copied = true
                        }) {
                            Icon(
                                if (copied) Icons.Default.Check else Icons.Default.ContentCopy,
                                null,
                                modifier = Modifier.size(18.dp),
                            )
                            Spacer(Modifier.width(4.dp))
                            Text(if (copied) "已复制" else "复制")
                        }
                    }
                    Button(
                        onClick = { runCatching { uriHandler.openUri(manifest.shareUrl) } },
                        modifier = Modifier.fillMaxWidth(),
                        shape = MaterialTheme.shapes.extraLarge,
                    ) {
                        Text("打开加群链接")
                    }
                    TextButton(
                        onClick = onDismiss,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text("关闭")
                    }
                }
            }
        }
    }
}
