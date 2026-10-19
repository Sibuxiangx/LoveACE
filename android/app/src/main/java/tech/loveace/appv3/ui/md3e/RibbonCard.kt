package tech.loveace.appv3.ui.md3e

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import tech.loveace.appv3.ui.theme.LocalExtendedColors
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.dp

/**
 * 卡片色板变体（对齐小程序 m3-card）：tone 分层，不用边框和阴影。
 * hero 用 *_CONTAINER + 32dp 圆角，普通卡 SURFACE_LOW + 28dp，紧凑半宽 tile 24dp。
 */
enum class RibbonCardVariant {
    PRIMARY, PRIMARY_CONTAINER,
    SECONDARY_CONTAINER, TERTIARY_CONTAINER,
    ERROR_CONTAINER, SUCCESS_CONTAINER, WARNING_CONTAINER,
    SURFACE, SURFACE_LOW, SURFACE_CONTAINER, SURFACE_HIGH,
}

@Composable
fun ribbonContainerColor(variant: RibbonCardVariant): Color {
    val scheme = MaterialTheme.colorScheme
    val extended = LocalExtendedColors.current
    return when (variant) {
        RibbonCardVariant.PRIMARY -> scheme.primary
        RibbonCardVariant.PRIMARY_CONTAINER -> scheme.primaryContainer
        RibbonCardVariant.SECONDARY_CONTAINER -> scheme.secondaryContainer
        RibbonCardVariant.TERTIARY_CONTAINER -> scheme.tertiaryContainer
        RibbonCardVariant.ERROR_CONTAINER -> scheme.errorContainer
        RibbonCardVariant.SUCCESS_CONTAINER -> extended.successContainer
        RibbonCardVariant.WARNING_CONTAINER -> extended.warningContainer
        RibbonCardVariant.SURFACE -> scheme.surface
        RibbonCardVariant.SURFACE_LOW -> scheme.surfaceContainerLow
        RibbonCardVariant.SURFACE_CONTAINER -> scheme.surfaceContainer
        RibbonCardVariant.SURFACE_HIGH -> scheme.surfaceContainerHigh
    }
}

@Composable
fun ribbonContentColor(variant: RibbonCardVariant): Color {
    val scheme = MaterialTheme.colorScheme
    val extended = LocalExtendedColors.current
    return when (variant) {
        RibbonCardVariant.PRIMARY -> scheme.onPrimary
        RibbonCardVariant.PRIMARY_CONTAINER -> scheme.onPrimaryContainer
        RibbonCardVariant.SECONDARY_CONTAINER -> scheme.onSecondaryContainer
        RibbonCardVariant.TERTIARY_CONTAINER -> scheme.onTertiaryContainer
        RibbonCardVariant.ERROR_CONTAINER -> scheme.onErrorContainer
        RibbonCardVariant.SUCCESS_CONTAINER -> extended.onSuccessContainer
        RibbonCardVariant.WARNING_CONTAINER -> extended.onWarningContainer
        RibbonCardVariant.SURFACE -> scheme.onSurface
        RibbonCardVariant.SURFACE_LOW, RibbonCardVariant.SURFACE_CONTAINER,
        RibbonCardVariant.SURFACE_HIGH,
        -> scheme.onSurface
    }
}

/**
 * M3E 卡片（对齐小程序 m3-card）：
 * - 按压 morph：圆角收到 min(radius, 12) 并缩至 0.985，420ms 弹簧
 * - 无阴影无描边，tone 分层
 * - hero 卡：variant = *_CONTAINER, radius = 32.dp, padding 20-22
 */
@Composable
fun RibbonCard(
    modifier: Modifier = Modifier,
    variant: RibbonCardVariant = RibbonCardVariant.SURFACE_LOW,
    radius: androidx.compose.ui.unit.Dp = 28.dp,
    padding: PaddingValues = PaddingValues(20.dp),
    interactive: Boolean = false,
    onClick: () -> Unit = {},
    content: @Composable ColumnScope.() -> Unit,
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val corner by animateDpAsState(
        targetValue = if (pressed && interactive) minOf(radius, 12.dp) else radius,
        animationSpec = spring(dampingRatio = Spring.DampingRatioMediumBouncy, stiffness = Spring.StiffnessMediumLow),
        label = "ribbonCardCorner",
    )
    val scale by animateFloatAsState(
        targetValue = if (pressed && interactive) 0.985f else 1f,
        animationSpec = spring(dampingRatio = Spring.DampingRatioMediumBouncy, stiffness = Spring.StiffnessMediumLow),
        label = "ribbonCardScale",
    )

    Box(
        modifier = modifier
            .graphicsLayer {
                scaleX = scale
                scaleY = scale
            }
            .clip(RoundedCornerShape(corner))
            .background(ribbonContainerColor(variant))
            .then(
                if (interactive) {
                    Modifier.clickable(interactionSource = interaction, indication = null, onClick = onClick)
                } else {
                    Modifier
                }
            )
            .padding(padding)
    ) {
        Column(content = content)
    }
}

/** 通宽便捷重载：绝大多数列表卡都是 fillMaxWidth + SURFACE_LOW + 28dp + 6-20 padding */
@Composable
fun RibbonListCard(
    modifier: Modifier = Modifier,
    interactive: Boolean = false,
    onClick: () -> Unit = {},
    content: @Composable ColumnScope.() -> Unit,
) {
    RibbonCard(
        modifier = modifier.fillMaxWidth(),
        variant = RibbonCardVariant.SURFACE_LOW,
        radius = 28.dp,
        padding = PaddingValues(vertical = 6.dp),
        interactive = interactive,
        onClick = onClick,
        content = content,
    )
}
