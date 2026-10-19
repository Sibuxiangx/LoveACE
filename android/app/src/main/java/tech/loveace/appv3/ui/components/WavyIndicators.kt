package tech.loveace.appv3.ui.components

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.unit.dp
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

private val WAVE_AMPLITUDE = 2.dp
private val WAVE_LENGTH = 16.dp
private val WAVE_STROKE = 4.dp

/**
 * M3E 波形进度条（线性，自绘）：material3 1.4 stable 暂缺 Wavy 组件，
 * 这里按 M3E 规格手绘（波幅 2dp / 波长 16dp / 4dp 圆帽），1.5 稳定后可换回官方实现。
 * progress == null 表示不确定进度（波形相位滚动）。
 */
@Composable
fun WavyLinearProgressIndicator(
    progress: (() -> Float)?,
    modifier: Modifier = Modifier,
    color: Color,
    trackColor: Color,
) {
    val phase: Float = if (progress == null) {
        val transition = rememberInfiniteTransition(label = "wavyLinear")
        val p by transition.animateFloat(
            initialValue = 0f,
            targetValue = (2.0 * Math.PI).toFloat(),
            animationSpec = infiniteRepeatable(tween(1600, easing = LinearEasing)),
            label = "wavyLinearPhase",
        )
        p
    } else {
        remember { mutableFloatStateOf(0f) }.floatValue
    }

    Canvas(modifier = modifier) {
        val stroke = WAVE_STROKE.toPx()
        val amplitude = WAVE_AMPLITUDE.toPx()
        val wavelength = WAVE_LENGTH.toPx()
        val midY = size.height / 2f

        drawLine(
            color = trackColor,
            start = Offset(0f, midY),
            end = Offset(size.width, midY),
            strokeWidth = stroke,
            cap = StrokeCap.Round,
        )

        val waveWidth = progress?.let { size.width * it().coerceIn(0f, 1f) } ?: size.width
        if (waveWidth <= stroke) return@Canvas

        val step = 6f
        var prev = Offset(0f, midY + amplitude * sin(-phase.toDouble()).toFloat())
        var x = 0f
        while (x <= waveWidth) {
            val next = Offset(
                x,
                midY + amplitude * sin(2.0 * Math.PI * x / wavelength - phase.toDouble()).toFloat(),
            )
            drawLine(color, prev, next, strokeWidth = stroke, cap = StrokeCap.Round)
            prev = next
            x += step
        }
        // M3E 波形末端的停止点
        drawCircle(color, radius = stroke * 0.7f, center = Offset(waveWidth, midY))
    }
}

/**
 * M3E 波形进度环（圆形，自绘）：8 瓣圆环；不确定进度整环旋转，
 * 确定进度按弧段展开（弧段上半径随角度波动）。
 */
@Composable
fun WavyCircularProgressIndicator(
    progress: (() -> Float)?,
    modifier: Modifier = Modifier,
    color: Color,
    trackColor: Color,
) {
    val rotation: Float = if (progress == null) {
        val transition = rememberInfiniteTransition(label = "wavyCircular")
        val r by transition.animateFloat(
            initialValue = 0f,
            targetValue = 360f,
            animationSpec = infiniteRepeatable(tween(1800, easing = LinearEasing)),
            label = "wavyCircularRotation",
        )
        r
    } else {
        remember { mutableFloatStateOf(0f) }.floatValue
    }

    Canvas(modifier = modifier) {
        val stroke = WAVE_STROKE.toPx()
        val radius = (min(size.width, size.height) - stroke) / 2f
        val amplitude = 1.5.dp.toPx()
        val lobes = 8
        val steps = 120

        drawCircle(trackColor, radius = radius, style = Stroke(stroke))

        fun drawWaveArc(sweepDeg: Float) {
            var prev: Offset? = null
            for (i in 0..steps) {
                val angleDeg = sweepDeg * i / steps
                val rad = Math.toRadians(angleDeg.toDouble())
                val r = radius + amplitude * sin((lobes * rad).toDouble()).toFloat()
                val point = Offset(
                    center.x + r * cos(rad).toFloat(),
                    center.y + r * sin(rad).toFloat(),
                )
                prev?.let { drawLine(color, it, point, strokeWidth = stroke, cap = StrokeCap.Round) }
                prev = point
            }
        }

        val sweep = progress?.let { 360f * it().coerceIn(0f, 1f) } ?: 300f
        rotate(degrees = rotation) {
            drawWaveArc(sweep)
        }
    }
}
