package tech.loveace.appv3.ui.screen

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PersistableBundle
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Gesture
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.PointMode
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalViewConfiguration
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.withTimeoutOrNull
import tech.loveace.appv3.ui.components.AppCircularProgressIndicator
import tech.loveace.appv3.ui.md3e.RibbonCard
import tech.loveace.appv3.ui.md3e.RibbonCardVariant
import tech.loveace.appv3.ui.md3e.RibbonState
import tech.loveace.appv3.ui.md3e.RibbonStateKind
import tech.loveace.appv3.ui.viewmodel.AuthViewModel
import tech.loveace.appv3.ui.viewmodel.MailPasswordViewModel

/** 拷贝后的剪贴板清除延迟：Android 无法给剪贴板设置过期时间，只能自行延时清除 */
private const val CLIPBOARD_CLEAR_DELAY_MS = 60_000L

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MailPasswordScreen(authViewModel: AuthViewModel, onBack: () -> Unit, vm: MailPasswordViewModel = viewModel()) {
    val state by vm.uiState.collectAsStateWithLifecycle()

    LaunchedEffect(authViewModel.portalService) { vm.load(authViewModel.portalService) }
    // 离开页面后清除内存中的初始密码，迟到的请求结果也会被 generation 丢弃
    DisposableEffect(Unit) { onDispose { vm.clear() } }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("企业邮箱初始密码") },
                navigationIcon = {
                    IconButton(onClick = { vm.clear(); onBack() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, "返回")
                    }
                },
            )
        },
    ) { padding ->
        Column(
            Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 96.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            val password = state.password
            when {
                password != null -> {
                    if (password.loginId.isNotBlank()) LoginIdLine(password.loginId)
                    ScratchPasswordCard(password.password)
                    state.error?.let { message ->
                        RefreshErrorRow(message) { vm.load(authViewModel.portalService) }
                    }
                }
                state.isLoading || !state.hasLoaded -> Box(
                    Modifier.fillMaxWidth().padding(vertical = 48.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    AppCircularProgressIndicator(modifier = Modifier.size(48.dp))
                }
                state.error != null -> RibbonState(
                    kind = RibbonStateKind.ERROR,
                    title = "无法获取初始密码",
                    description = state.error,
                    actionText = "重试",
                    onAction = { vm.load(authViewModel.portalService) },
                )
                else -> RibbonState(
                    kind = RibbonStateKind.EMPTY,
                    title = "暂无初始密码",
                    description = "学校系统中没有这条记录。",
                )
            }
            Text(
                "初始密码只在本页显示，离开页面后自动清除。拷贝的内容 60 秒后从剪贴板失效。",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 6.dp),
            )
        }
    }
}

@Composable
private fun LoginIdLine(loginId: String) {
    Column(Modifier.padding(horizontal = 6.dp)) {
        Text("登录名", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(loginId, style = MaterialTheme.typography.bodyLarge)
    }
}

/** 刮刮卡：密码在下层，表面覆盖一层 surface 色遮罩，拖动或单击时用 BlendMode.Clear 擦除；长按拷贝 */
@Composable
private fun ScratchPasswordCard(password: String) {
    val context = LocalContext.current
    val viewConfiguration = LocalViewConfiguration.current
    val touchSlop = viewConfiguration.touchSlop
    val longPressTimeout = viewConfiguration.longPressTimeoutMillis
    val coverColor = MaterialTheme.colorScheme.surface
    val strokes = remember(password) { mutableStateListOf<List<Offset>>() }
    val liveStroke = remember(password) { mutableStateListOf<Offset>() }
    var copyCount by remember { mutableIntStateOf(0) }
    var showCopied by remember { mutableStateOf(false) }

    LaunchedEffect(copyCount) {
        if (copyCount > 0) {
            showCopied = true
            delay(2_000)
            showCopied = false
        }
    }

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        RibbonCard(
            modifier = Modifier.fillMaxWidth(),
            variant = RibbonCardVariant.SURFACE_HIGH,
            radius = 16.dp,
            padding = PaddingValues(0.dp),
        ) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(132.dp)
                    .pointerInput(password) {
                        awaitEachGesture {
                            val down = awaitFirstDown()
                            liveStroke.clear()
                            liveStroke.add(down.position)
                            var moved = false
                            var longPressed = false
                            var pressed = true
                            while (pressed) {
                                val event = if (moved || longPressed) {
                                    awaitPointerEvent()
                                } else {
                                    withTimeoutOrNull(longPressTimeout) { awaitPointerEvent() }
                                }
                                if (event == null) {
                                    // 按住不动达到长按时长：拷贝密码，本次按压不再刮开
                                    longPressed = true
                                    liveStroke.clear()
                                    copyPasswordToClipboard(context, password)
                                    copyCount += 1
                                    continue
                                }
                                val change = event.changes.firstOrNull { it.id == down.id } ?: break
                                pressed = change.pressed
                                if (!longPressed) {
                                    if (!moved && (change.position - down.position).getDistance() > touchSlop) {
                                        moved = true
                                    }
                                    if (moved) {
                                        liveStroke.add(change.position)
                                        change.consume()
                                    }
                                }
                            }
                            // 单击时 liveStroke 只有按下点，会擦出一个圆点
                            if (!longPressed && liveStroke.isNotEmpty()) strokes.add(liveStroke.toList())
                            liveStroke.clear()
                        }
                    },
            ) {
                Text(
                    password,
                    modifier = Modifier.align(Alignment.Center).padding(horizontal = 16.dp),
                    style = MaterialTheme.typography.titleLarge.copy(
                        fontFamily = FontFamily.Monospace,
                        fontWeight = FontWeight.SemiBold,
                    ),
                    textAlign = TextAlign.Center,
                )
                Canvas(
                    Modifier
                        .matchParentSize()
                        .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen },
                ) {
                    drawRoundRect(color = coverColor, cornerRadius = CornerRadius(16.dp.toPx()))
                    strokes.forEach { eraseStroke(it) }
                    eraseStroke(liveStroke)
                }
                if (strokes.isEmpty() && liveStroke.isEmpty()) {
                    Row(Modifier.align(Alignment.Center), verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            Icons.Default.Gesture,
                            null,
                            modifier = Modifier.size(18.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Spacer(Modifier.width(6.dp))
                        Text(
                            "按住并滑动，刮开密码",
                            style = MaterialTheme.typography.labelLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (showCopied) {
                Icon(Icons.Default.Check, null, modifier = Modifier.size(16.dp), tint = MaterialTheme.colorScheme.primary)
                Spacer(Modifier.width(4.dp))
                Text("已拷贝", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
            }
            Spacer(Modifier.weight(1f))
            FilledTonalButton(onClick = {
                copyPasswordToClipboard(context, password)
                copyCount += 1
            }) {
                Icon(Icons.Default.ContentCopy, null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(6.dp))
                Text("拷贝密码")
            }
            Spacer(Modifier.width(8.dp))
            TextButton(onClick = { strokes.clear() }, enabled = strokes.isNotEmpty()) {
                Text("重新遮盖")
            }
        }
    }
}

/** 用 BlendMode.Clear 擦除一条轨迹；单点为圆点，多点按线段绘制，端点为圆头 */
private fun DrawScope.eraseStroke(points: List<Offset>) {
    val width = 44.dp.toPx()
    if (points.size == 1) {
        drawPoints(
            points = points,
            pointMode = PointMode.Points,
            color = Color.Transparent,
            strokeWidth = width,
            cap = StrokeCap.Round,
            blendMode = BlendMode.Clear,
        )
        return
    }
    for (i in 1 until points.size) {
        drawLine(
            color = Color.Transparent,
            start = points[i - 1],
            end = points[i],
            strokeWidth = width,
            cap = StrokeCap.Round,
            blendMode = BlendMode.Clear,
        )
    }
}

@Composable
private fun RefreshErrorRow(message: String, onRetry: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            message,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.error,
            modifier = Modifier.weight(1f),
        )
        TextButton(onClick = onRetry) { Text("重试") }
    }
}

private fun copyPasswordToClipboard(context: Context, password: String) {
    val clipboard = context.getSystemService(ClipboardManager::class.java) ?: return
    val clip = ClipData.newPlainText("", password)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        clip.description.extras = PersistableBundle().apply {
            putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true)
        }
    }
    clipboard.setPrimaryClip(clip)
    // Android 不能给剪贴板设置过期时间，这里延时检查并清除
    val appContext = context.applicationContext
    Handler(Looper.getMainLooper()).postDelayed(
        { clearClipboardIfUnchanged(appContext, password) },
        CLIPBOARD_CLEAR_DELAY_MS,
    )
}

/** 仅当剪贴板仍是同一段密码文本时才清除；读取失败（后台限制）则跳过 */
private fun clearClipboardIfUnchanged(context: Context, password: String) {
    val clipboard = context.getSystemService(ClipboardManager::class.java) ?: return
    try {
        val clip = clipboard.primaryClip ?: return
        if (clip.itemCount == 0 || clip.getItemAt(0).text?.toString() != password) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            clipboard.clearPrimaryClip()
        } else {
            clipboard.setPrimaryClip(ClipData.newPlainText("", ""))
        }
    } catch (_: SecurityException) {
        // 无法读取剪贴板时跳过清除
    }
}
