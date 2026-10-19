package tech.loveace.appv3.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

val AppTypography = Typography(
    displayLarge = TextStyle(fontSize = 57.sp, fontWeight = FontWeight.Normal, lineHeight = 64.sp),
    displayMedium = TextStyle(fontSize = 45.sp, fontWeight = FontWeight.Normal, lineHeight = 52.sp),
    displaySmall = TextStyle(fontSize = 36.sp, fontWeight = FontWeight.Normal, lineHeight = 44.sp),
    headlineLarge = TextStyle(fontSize = 32.sp, fontWeight = FontWeight.SemiBold, lineHeight = 40.sp),
    headlineMedium = TextStyle(fontSize = 28.sp, fontWeight = FontWeight.SemiBold, lineHeight = 36.sp),
    headlineSmall = TextStyle(fontSize = 24.sp, fontWeight = FontWeight.SemiBold, lineHeight = 32.sp),
    titleLarge = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.SemiBold, lineHeight = 28.sp),
    titleMedium = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.SemiBold, lineHeight = 24.sp, letterSpacing = 0.15.sp),
    titleSmall = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.SemiBold, lineHeight = 20.sp, letterSpacing = 0.1.sp),
    bodyLarge = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.Normal, lineHeight = 24.sp, letterSpacing = 0.5.sp),
    bodyMedium = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Normal, lineHeight = 20.sp, letterSpacing = 0.25.sp),
    bodySmall = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Normal, lineHeight = 16.sp, letterSpacing = 0.4.sp),
    labelLarge = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.SemiBold, lineHeight = 20.sp, letterSpacing = 0.1.sp),
    labelMedium = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.SemiBold, lineHeight = 16.sp, letterSpacing = 0.5.sp),
    labelSmall = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.SemiBold, lineHeight = 16.sp, letterSpacing = 0.5.sp),
)

/**
 * M3E 重数字样式：统计数字、金额、日期一律用它（对齐小程序 weight 800 规范）。
 * 下方注释的尺寸按内容层级取用，letterSpacing 收紧让大数字更紧凑。
 */
object RibbonNumeric {
    val XL = TextStyle(fontSize = 56.sp, fontWeight = FontWeight(800), lineHeight = 60.sp, letterSpacing = (-1).sp)
    val Large = TextStyle(fontSize = 28.sp, fontWeight = FontWeight(800), lineHeight = 32.sp, letterSpacing = (-0.5).sp)
    val Medium = TextStyle(fontSize = 18.sp, fontWeight = FontWeight(800), lineHeight = 24.sp)
    /** 数字下方的小注释（10-11sp / 700 / 宽字距） */
    val Caption = TextStyle(fontSize = 11.sp, fontWeight = FontWeight(700), lineHeight = 14.sp, letterSpacing = 0.5.sp)
}
