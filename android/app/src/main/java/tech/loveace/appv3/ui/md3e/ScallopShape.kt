package tech.loveace.appv3.ui.md3e

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

/**
 * M3E 花形（scallop）轮廓族：r = r0 × (1 + amp·cos(lobes·θ))。
 * 与小程序 m3-shape、kazumi-me 徽章是同一个极坐标公式（120+ 点多边形）。
 * 挑形看搭配（相邻元素不同形），不看语义；语义状态见 RibbonState 的固定映射。
 */
enum class RibbonShape(val lobes: Int, val amplitude: Float) {
    COOKIE_12(12, 0.045f),
    COOKIE_8(8, 0.065f),
    COOKIE_6(6, 0.085f),
    FLOWER_5(5, 0.11f),
    PEBBLE_3(3, 0.09f),
    CLOVER_4(4, 0.16f),
}

/** 花形 [Shape] 实现；半径按短边缩放，非正方形容器里不越界 */
class ScallopShape(private val shape: RibbonShape) : Shape {
    override fun createOutline(
        size: Size,
        layoutDirection: LayoutDirection,
        density: Density,
    ): Outline {
        val path = Path()
        val steps = 240
        val centerX = size.width / 2f
        val centerY = size.height / 2f
        // 100 单位视框里 badge 半径 47（留 3 单位呼吸），按短边换算
        val radius = min(size.width, size.height) / 2f * (47f / 50f)
        for (i in 0 until steps) {
            val t = (2.0 * Math.PI * i) / steps
            val r = radius * (1.0 + shape.amplitude * cos(shape.lobes * t)) / (1.0 + shape.amplitude)
            val x = centerX + (r * sin(t)).toFloat()
            val y = centerY - (r * cos(t)).toFloat()
            if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
        }
        path.close()
        return Outline.Generic(path)
    }
}
