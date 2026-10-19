package tech.loveace.appv3.ui.md3e

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.graphicsLayer
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.min
import kotlin.math.sin

/**
 * M3E 花形 morph loading（对齐小程序 m3-loading，但用路径插值而非透明度交叠）：
 * 3.6s 旋转一圈，形状沿 cookie8 → clover4 → flower5 → cookie8 连续变形
 * （所有花形共用 240 点极坐标骨架，逐点半径插值，动画全程无切换跳变），
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
    val scale = 1f - 0.14f * abs(sin(phase * 2.0 * Math.PI).toFloat())

    Box(modifier, contentAlignment = Alignment.Center) {
        Canvas(
            Modifier
                .fillMaxSize()
                .graphicsLayer {
                    rotationZ = rotation
                    scaleX = scale
                    scaleY = scale
                }
        ) {
            // draw 相位读取 state，只触发重绘不重组
            val t = phase * MORPH_SEQUENCE.size
            val index = floor(t).toInt() % MORPH_SEQUENCE.size
            val nextIndex = (index + 1) % MORPH_SEQUENCE.size
            val frac = t - floor(t)
            // smoothstep 让变形在周期边界附近放缓，观感更接近回弹
            val k = (frac * frac * (3f - 2f * frac))

            drawScallop(MORPH_SEQUENCE[index], MORPH_SEQUENCE[nextIndex], k, color)
        }
    }
}

/** morph 序列：cookie8 → clover4 → flower5 → 回到 cookie8 */
private val MORPH_SEQUENCE = listOf(
    RibbonShape.COOKIE_8,
    RibbonShape.CLOVER_4,
    RibbonShape.FLOWER_5,
)

private const val MORPH_STEPS = 240

/** 逐点半径插值画出两个花形之间的中间形（点数相同、起始角相同，天然无缝） */
private fun DrawScope.drawScallop(
    from: RibbonShape,
    to: RibbonShape,
    k: Float,
    color: Color,
) {
    val radius = min(size.width, size.height) / 2f * (47f / 50f)
    val path = Path()
    for (i in 0 until MORPH_STEPS) {
        val theta = (2.0 * Math.PI * i) / MORPH_STEPS
        val rFrom = radius * (1.0 + from.amplitude * cos(from.lobes * theta)) / (1.0 + from.amplitude)
        val rTo = radius * (1.0 + to.amplitude * cos(to.lobes * theta)) / (1.0 + to.amplitude)
        val r = rFrom + (rTo - rFrom) * k
        val x = center.x + (r * sin(theta)).toFloat()
        val y = center.y - (r * cos(theta)).toFloat()
        if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
    }
    path.close()
    drawPath(path, color)
}
