package tech.loveace.appv3.ui.md3e

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import kotlin.math.abs
import kotlin.math.sin

/**
 * M3E 花形 morph loading（对齐小程序 m3-loading）：
 * 3.6s 旋转一圈，形状按 cookie8 → clover4 → flower5 每 1.2s 轮换，
 * 同时缩放 1 → 0.86 → 1 呼吸两次。尺寸完全由外部 modifier 决定。
 */
@Composable
fun RibbonShapeLoader(
    modifier: Modifier = Modifier,
    color: Color = MaterialTheme.colorScheme.primary,
) {
    val transition = rememberInfiniteTransition(label = "ribbonShapeLoader")
    val rotation by transition.animateFloat(
        initialValue = 0f,
        targetValue = 360f,
        animationSpec = infiniteRepeatable(tween(3600, easing = LinearEasing)),
        label = "loaderRotation",
    )
    val phase by transition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(3600, easing = LinearEasing)),
        label = "loaderPhase",
    )

    // 缩放 1 → 0.86 → 1（sin 一个完整周期内两次压缩）
    val scale = 1f - 0.14f * abs(sin(phase * 2.0 * Math.PI))
    // 每 1/3 周期换一个形状：cookie8 → clover4 → flower5
    val shapes = listOf(RibbonShape.COOKIE_8, RibbonShape.CLOVER_4, RibbonShape.FLOWER_5)
    val shapeIndex = ((phase * 3.0).toInt()) % shapes.size

    Box(modifier, contentAlignment = Alignment.Center) {
        Box(
            Modifier
                .fillMaxSize()
                .graphicsLayer {
                    rotationZ = rotation
                    scaleX = scale
                    scaleY = scale
                }
                .clip(ScallopShape(shapes[shapeIndex]))
                .background(color),
        )
    }
}
