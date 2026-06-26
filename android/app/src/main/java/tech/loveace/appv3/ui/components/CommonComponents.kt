package tech.loveace.appv3.ui.components

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import tech.loveace.appv3.ui.theme.LocalProgressBarStyle
import tech.loveace.appv3.ui.theme.ProgressBarStyle

@Composable
fun LoadingScreen(message: String = "加载中...") {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            AppCircularProgressIndicator()
            Spacer(Modifier.height(20.dp))
            Text(message, style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
fun ErrorScreen(message: String, onRetry: (() -> Unit)? = null) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.padding(40.dp),
        ) {
            Text("😵", style = MaterialTheme.typography.displayMedium)
            Spacer(Modifier.height(20.dp))
            Text(message, style = MaterialTheme.typography.bodyLarge, textAlign = TextAlign.Center)
            if (onRetry != null) {
                Spacer(Modifier.height(20.dp))
                FilledTonalButton(
                    onClick = onRetry,
                    shape = MaterialTheme.shapes.large,
                ) { Text("重试") }
            }
        }
    }
}

@Composable
fun EmptyScreen(message: String = "暂无数据") {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text("📭", style = MaterialTheme.typography.displayMedium)
            Spacer(Modifier.height(16.dp))
            Text(message, style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
fun StatCard(
    title: String,
    value: String,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    containerColor: Color = MaterialTheme.colorScheme.primaryContainer,
    contentColor: Color = MaterialTheme.colorScheme.onPrimaryContainer,
) {
    Card(
        modifier = modifier.animateContentSize(),
        colors = CardDefaults.cardColors(containerColor = containerColor, contentColor = contentColor),
        shape = MaterialTheme.shapes.large,
    ) {
        Column(Modifier.padding(20.dp)) {
            Text(title, style = MaterialTheme.typography.labelMedium)
            Spacer(Modifier.height(6.dp))
            Text(value, style = MaterialTheme.typography.headlineMedium)
            if (subtitle != null) {
                Spacer(Modifier.height(4.dp))
                Text(subtitle, style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

/** 根据用户偏好选择波浪或标准风格的圆形进度指示器 */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun AppCircularProgressIndicator(
    modifier: Modifier = Modifier,
    color: Color = MaterialTheme.colorScheme.primary,
    trackColor: Color = MaterialTheme.colorScheme.surfaceContainerHighest,
) {
    val style = LocalProgressBarStyle.current
    when (style) {
        ProgressBarStyle.WAVY -> CircularWavyProgressIndicator(modifier = modifier, color = color, trackColor = trackColor)
        ProgressBarStyle.STANDARD -> CircularProgressIndicator(modifier = modifier, color = color)
    }
}

/** 根据用户偏好选择波浪或标准风格的圆形进度指示器（确定进度） */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun AppCircularProgressIndicator(
    progress: () -> Float,
    modifier: Modifier = Modifier,
    color: Color = MaterialTheme.colorScheme.primary,
    trackColor: Color = MaterialTheme.colorScheme.surfaceContainerHighest,
) {
    val style = LocalProgressBarStyle.current
    when (style) {
        ProgressBarStyle.WAVY -> CircularWavyProgressIndicator(progress = progress, modifier = modifier, color = color, trackColor = trackColor)
        ProgressBarStyle.STANDARD -> CircularProgressIndicator(progress = progress, modifier = modifier, color = color, trackColor = trackColor)
    }
}

/** 根据用户偏好选择波浪或标准风格的线性进度条 */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun AppLinearProgressIndicator(
    modifier: Modifier = Modifier,
    color: Color = MaterialTheme.colorScheme.primary,
    trackColor: Color = MaterialTheme.colorScheme.surfaceContainerHighest,
) {
    val style = LocalProgressBarStyle.current
    when (style) {
        ProgressBarStyle.WAVY -> LinearWavyProgressIndicator(modifier = modifier, color = color, trackColor = trackColor)
        ProgressBarStyle.STANDARD -> LinearProgressIndicator(modifier = modifier, color = color, trackColor = trackColor)
    }
}

/** 根据用户偏好选择波浪或标准风格的线性进度条（确定进度） */
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun AppLinearProgressIndicator(
    progress: () -> Float,
    modifier: Modifier = Modifier,
    color: Color = MaterialTheme.colorScheme.primary,
    trackColor: Color = MaterialTheme.colorScheme.surfaceContainerHighest,
) {
    val style = LocalProgressBarStyle.current
    when (style) {
        ProgressBarStyle.WAVY -> LinearWavyProgressIndicator(progress = progress, modifier = modifier, color = color, trackColor = trackColor)
        ProgressBarStyle.STANDARD -> LinearProgressIndicator(progress = progress, modifier = modifier, color = color, trackColor = trackColor)
    }
}

/** 带图标背景的 Tonal 图标容器 */
@Composable
fun TonalIconBox(
    icon: ImageVector,
    modifier: Modifier = Modifier,
    containerColor: Color = MaterialTheme.colorScheme.primaryContainer,
    contentColor: Color = MaterialTheme.colorScheme.onPrimaryContainer,
    size: Dp = 44.dp,
    iconSize: Dp = 22.dp,
) {
    Box(
        modifier = modifier
            .size(size)
            .background(containerColor, CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, null, modifier = Modifier.size(iconSize), tint = contentColor)
    }
}

/** Section 标题 */
@Composable
fun SectionTitle(
    title: String,
    modifier: Modifier = Modifier,
) {
    Text(
        title,
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.primary,
        modifier = modifier.padding(vertical = 4.dp),
    )
}
