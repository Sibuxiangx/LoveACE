package tech.loveace.appv3.ui.md3e

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * 花形徽章容器（对齐小程序 m3-shape）：花形容器 + 居中图标。
 * 图标默认取徽章尺寸的 46%；列表徽章 44dp 起，hero 56-60dp。
 */
@Composable
fun ShapeBadge(
    shape: RibbonShape,
    modifier: Modifier = Modifier,
    size: Dp = 44.dp,
    color: Color = MaterialTheme.colorScheme.primaryContainer,
    icon: ImageVector? = null,
    iconTint: Color = MaterialTheme.colorScheme.onPrimaryContainer,
    iconSizeFraction: Float = 0.46f,
    content: @Composable () -> Unit = {},
) {
    Box(
        modifier = modifier
            .size(size)
            .clip(ScallopShape(shape))
            .background(color),
        contentAlignment = Alignment.Center,
    ) {
        if (icon != null) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                modifier = Modifier.size(size * iconSizeFraction),
                tint = iconTint,
            )
        }
        content()
    }
}
