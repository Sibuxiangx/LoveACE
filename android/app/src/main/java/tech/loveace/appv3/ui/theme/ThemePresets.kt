package tech.loveace.appv3.ui.theme

import androidx.compose.runtime.Immutable
import com.materialkolor.hct.Hct
import com.materialkolor.palettes.TonalPalette
import kotlin.math.abs

/**
 * 彩带品牌预设色。每个预设用 HCT 色相/彩度定义（低饱和 calm 调性），
 * 完整明暗 scheme 由 Material Color Utilities 生成（见 Theme.schemeFromPreset），
 * tone 映射与小程序版 DESIGN.md §2.3 保持一致。
 */
@Immutable
data class ThemePreset(
    val id: String,
    val name: String,
    val hue: Double,
    val chroma: Double,
) {
    /** 设置页色板展示用主色（tone 40） */
    val seedArgb: Int get() = TonalPalette.fromHueAndChroma(hue, chroma).tone(40)
}

object ThemePresets {
    /** 松青（默认）：低饱和松绿，安静耐看 */
    val PINE = ThemePreset("pine", "松青", hue = 155.0, chroma = 24.0)
    val SATIN_PURPLE = ThemePreset("satin_purple", "缎紫", hue = 275.0, chroma = 28.0)
    val CHERRY = ThemePreset("cherry", "樱红", hue = 355.0, chroma = 30.0)
    val APRICOT = ThemePreset("apricot", "杏黄", hue = 75.0, chroma = 32.0)

    /** 湖蓝：与小程序版默认预设一致 */
    val LAKE = ThemePreset("lake", "湖蓝", hue = 212.6, chroma = 26.8)

    /** 黛墨：近无彩度，与小程序版 ink 一致 */
    val INK = ThemePreset("ink", "黛墨", hue = 240.0, chroma = 9.0)

    val DEFAULT = PINE
    val ALL = listOf(PINE, SATIN_PURPLE, CHERRY, APRICOT, LAKE, INK)
    private val BY_ID = ALL.associateBy { it.id }

    fun byId(id: String): ThemePreset = BY_ID[id] ?: DEFAULT

    /** 旧版种子色（ARGB）迁移：按 HCT 色相距离映射到最近的预设 */
    fun migrateLegacySeed(argb: Int): String {
        val hct = Hct.fromInt(argb)
        return ALL.minByOrNull { preset ->
            val d = abs(preset.hue - hct.hue)
            minOf(d, 360.0 - d)
        }?.id ?: DEFAULT.id
    }
}
