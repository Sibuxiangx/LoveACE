package tech.loveace.appv3.ui.theme

import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import com.materialkolor.palettes.TonalPalette

/**
 * M3 核心之外的两个语义角色（对齐小程序 success/warning token）：
 * success = 已完成/达标/有效，warning = 即将到期/部分完成。
 */
@Immutable
data class ExtendedColors(
    val success: Color,
    val onSuccess: Color,
    val successContainer: Color,
    val onSuccessContainer: Color,
    val warning: Color,
    val onWarning: Color,
    val warningContainer: Color,
    val onWarningContainer: Color,
)

val LocalExtendedColors = staticCompositionLocalOf {
    // 湖蓝预设的静态兜底值（与小程序 DESIGN.md §2.1 一致）
    ExtendedColors(
        success = Color(0xFF41673D), onSuccess = Color.White,
        successContainer = Color(0xFFC2EEB9), onSuccessContainer = Color(0xFF0D260B),
        warning = Color(0xFF855303), onWarning = Color.White,
        warningContainer = Color(0xFFFFDDB8), onWarningContainer = Color(0xFF2B1800),
    )
}

/** success/warning 的 tone 布局与 accent 一致（40/80、90/30、100/20、10/90） */
internal fun extendedColorsFromPreset(isDark: Boolean): ExtendedColors {
    val success = TonalPalette.fromHueAndChroma(145.0, 32.0)
    val warning = TonalPalette.fromHueAndChroma(70.0, 40.0)
    return if (isDark) {
        ExtendedColors(
            success = Color(success.tone(80)), onSuccess = Color(success.tone(20)),
            successContainer = Color(success.tone(30)), onSuccessContainer = Color(success.tone(90)),
            warning = Color(warning.tone(80)), onWarning = Color(warning.tone(20)),
            warningContainer = Color(warning.tone(30)), onWarningContainer = Color(warning.tone(90)),
        )
    } else {
        ExtendedColors(
            success = Color(success.tone(40)), onSuccess = Color(success.tone(100)),
            successContainer = Color(success.tone(90)), onSuccessContainer = Color(success.tone(10)),
            warning = Color(warning.tone(40)), onWarning = Color(warning.tone(100)),
            warningContainer = Color(warning.tone(90)), onWarningContainer = Color(warning.tone(10)),
        )
    }
}
