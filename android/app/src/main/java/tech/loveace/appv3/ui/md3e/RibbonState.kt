package tech.loveace.appv3.ui.md3e

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Inbox
import androidx.compose.material.icons.rounded.Person
import androidx.compose.material.icons.rounded.SyncProblem
import androidx.compose.material.icons.rounded.WifiOff
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import tech.loveace.appv3.ui.components.AppCircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * 全页状态（对齐 m3-state）：loading / empty(cookie6) / error(flower5) /
 * offline(cookie12) / login(cookie8)。96dp 徽章 + 18sp 标题 + 小说明 + 可选动作。
 */
enum class RibbonStateKind { LOADING, EMPTY, ERROR, OFFLINE, LOGIN }

@Composable
fun RibbonState(
    kind: RibbonStateKind,
    title: String,
    modifier: Modifier = Modifier,
    description: String? = null,
    actionText: String? = null,
    onAction: () -> Unit = {},
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp, vertical = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        when (kind) {
            RibbonStateKind.LOADING -> {
                Spacer(Modifier.height(28.dp))
                AppCircularProgressIndicator(modifier = Modifier.size(48.dp))
                Spacer(Modifier.height(28.dp))
            }
            else -> {
                val (shape, icon) = when (kind) {
                    RibbonStateKind.EMPTY -> RibbonShape.COOKIE_6 to Icons.Rounded.Inbox
                    RibbonStateKind.ERROR -> RibbonShape.FLOWER_5 to Icons.Rounded.SyncProblem
                    RibbonStateKind.OFFLINE -> RibbonShape.COOKIE_12 to Icons.Rounded.WifiOff
                    else -> RibbonShape.COOKIE_8 to Icons.Rounded.Person
                }
                Spacer(Modifier.height(12.dp))
                ShapeBadge(
                    shape = shape,
                    size = 96.dp,
                    color = MaterialTheme.colorScheme.primaryContainer,
                    icon = icon,
                    iconTint = MaterialTheme.colorScheme.onPrimaryContainer,
                    iconSizeFraction = 0.46f,
                )
                Spacer(Modifier.height(4.dp))
            }
        }
        Text(
            title,
            fontSize = 18.sp,
            fontWeight = FontWeight.SemiBold,
            lineHeight = 24.sp,
            color = MaterialTheme.colorScheme.onSurface,
            textAlign = TextAlign.Center,
        )
        if (description != null) {
            Text(
                description,
                fontSize = 13.sp,
                lineHeight = 19.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
        if (actionText != null) {
            Spacer(Modifier.height(10.dp))
            Button(onClick = onAction) {
                Text(actionText, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

/**
 * 骨架占位（对齐 m3-skeleton）：1.4s 呼吸脉冲，尺寸/圆角照它替身的内容定。
 */
@Composable
fun RibbonSkeleton(
    modifier: Modifier = Modifier,
    height: androidx.compose.ui.unit.Dp = 16.dp,
    radius: androidx.compose.ui.unit.Dp = 8.dp,
) {
    val transition = rememberInfiniteTransition(label = "skeleton")
    val alpha by transition.animateFloat(
        initialValue = 0.55f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(700, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "skeletonAlpha",
    )
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(height)
            .graphicsLayer { this.alpha = alpha }
            .clip(RoundedCornerShape(radius))
            .background(MaterialTheme.colorScheme.surfaceContainerHigh),
    )
}
