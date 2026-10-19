package tech.loveace.appv3.ui.theme

import android.app.Activity
import android.app.Application
import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.Density
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.materialkolor.palettes.TonalPalette
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/** 全局可读的深色模式状态，由 RibbonTheme 提供 */
val LocalIsDarkTheme = staticCompositionLocalOf { false }
/** 全局可读的进度条风格，由 RibbonTheme 提供 */
val LocalProgressBarStyle = staticCompositionLocalOf { ProgressBarStyle.WAVY }

class ThemeViewModel(application: Application) : AndroidViewModel(application) {
    private val prefs = ThemePreferences(application)

    val themeConfig = prefs.themeConfig.stateIn(
        viewModelScope, SharingStarted.WhileSubscribed(5000), ThemeConfig()
    )

    fun setPreset(presetId: String) = viewModelScope.launch { prefs.setPreset(presetId) }
    fun setDarkMode(mode: DarkMode) = viewModelScope.launch { prefs.setDarkMode(mode) }
    fun setDynamicColor(enabled: Boolean) = viewModelScope.launch { prefs.setDynamicColor(enabled) }
    fun setCourseNotification(enabled: Boolean) = viewModelScope.launch { prefs.setCourseNotification(enabled) }
    fun setProgressBarStyle(style: ProgressBarStyle) = viewModelScope.launch { prefs.setProgressBarStyle(style) }
}

/**
 * 由 Material Color Utilities（HCT）从预设色相/彩度组装 ColorScheme。
 * 调色板拆分与 tone 映射对齐小程序 DESIGN.md §2.3：
 * secondary = hue+3 & chroma×0.6、tertiary = hue+50 & chroma×0.8、
 * neutral = hue+3 & 4.5、neutralVariant = hue+4 & 8。
 */
private fun schemeFromPreset(preset: ThemePreset, isDark: Boolean): ColorScheme {
    val chroma = preset.chroma
    val primary = TonalPalette.fromHueAndChroma(preset.hue, chroma)
    val secondary = TonalPalette.fromHueAndChroma(preset.hue + 3.0, minOf(13.0, chroma * 0.6))
    val tertiary = TonalPalette.fromHueAndChroma(preset.hue + 50.0, minOf(22.0, chroma * 0.8))
    val neutral = TonalPalette.fromHueAndChroma(preset.hue + 3.0, 4.5)
    val neutralVariant = TonalPalette.fromHueAndChroma(preset.hue + 4.0, 8.0)
    val error = TonalPalette.fromHueAndChroma(25.0, 84.0)

    fun tone(p: TonalPalette, t: Int) = Color(p.tone(t))

    return if (isDark) {
        darkColorScheme(
            primary = tone(primary, 80),
            onPrimary = tone(primary, 20),
            primaryContainer = tone(primary, 30),
            onPrimaryContainer = tone(primary, 90),
            secondary = tone(secondary, 80),
            onSecondary = tone(secondary, 20),
            secondaryContainer = tone(secondary, 30),
            onSecondaryContainer = tone(secondary, 90),
            tertiary = tone(tertiary, 80),
            onTertiary = tone(tertiary, 20),
            tertiaryContainer = tone(tertiary, 30),
            onTertiaryContainer = tone(tertiary, 90),
            error = tone(error, 80),
            onError = tone(error, 20),
            errorContainer = tone(error, 30),
            onErrorContainer = tone(error, 90),
            background = tone(neutral, 6),
            onBackground = tone(neutral, 90),
            surface = tone(neutral, 6),
            onSurface = tone(neutral, 90),
            surfaceVariant = tone(neutralVariant, 30),
            onSurfaceVariant = tone(neutralVariant, 80),
            outline = tone(neutralVariant, 60),
            outlineVariant = tone(neutralVariant, 30),
            surfaceDim = tone(neutral, 6),
            surfaceBright = tone(neutral, 24),
            surfaceContainerLowest = tone(neutral, 4),
            surfaceContainerLow = tone(neutral, 10),
            surfaceContainer = tone(neutral, 12),
            surfaceContainerHigh = tone(neutral, 17),
            surfaceContainerHighest = tone(neutral, 22),
            inverseSurface = tone(neutral, 90),
            inverseOnSurface = tone(neutral, 20),
            inversePrimary = tone(primary, 40),
        )
    } else {
        lightColorScheme(
            primary = tone(primary, 40),
            onPrimary = tone(primary, 100),
            primaryContainer = tone(primary, 90),
            onPrimaryContainer = tone(primary, 10),
            secondary = tone(secondary, 40),
            onSecondary = tone(secondary, 100),
            secondaryContainer = tone(secondary, 90),
            onSecondaryContainer = tone(secondary, 10),
            tertiary = tone(tertiary, 40),
            onTertiary = tone(tertiary, 100),
            tertiaryContainer = tone(tertiary, 90),
            onTertiaryContainer = tone(tertiary, 10),
            error = tone(error, 40),
            onError = tone(error, 100),
            errorContainer = tone(error, 90),
            onErrorContainer = tone(error, 10),
            background = tone(neutral, 99),
            onBackground = tone(neutral, 10),
            surface = tone(neutral, 99),
            onSurface = tone(neutral, 10),
            surfaceVariant = tone(neutralVariant, 90),
            onSurfaceVariant = tone(neutralVariant, 30),
            outline = tone(neutralVariant, 50),
            outlineVariant = tone(neutralVariant, 80),
            surfaceDim = tone(neutral, 87),
            surfaceBright = tone(neutral, 99),
            surfaceContainerLowest = tone(neutral, 100),
            surfaceContainerLow = tone(neutral, 96),
            surfaceContainer = tone(neutral, 93),
            surfaceContainerHigh = tone(neutral, 91),
            surfaceContainerHighest = tone(neutral, 88),
            inverseSurface = tone(neutral, 20),
            inverseOnSurface = tone(neutral, 95),
            inversePrimary = tone(primary, 80),
        )
    }
}

@Composable
fun RibbonTheme(
    themeViewModel: ThemeViewModel = viewModel(),
    content: @Composable () -> Unit,
) {
    val config by themeViewModel.themeConfig.collectAsStateWithLifecycle()
    val systemDark = isSystemInDarkTheme()

    val isDark = when (config.darkMode) {
        DarkMode.SYSTEM -> systemDark
        DarkMode.LIGHT -> false
        DarkMode.DARK -> true
    }

    val preset = ThemePresets.byId(config.presetId)
    val colorScheme = when {
        config.useDynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (isDark) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }
        else -> schemeFromPreset(preset, isDark)
    }
    // 壁纸取色模式下 success/warning 仍由预设算法提供（系统动态 scheme 没有这两个角色）
    val extendedColors = remember(preset, isDark) { extendedColorsFromPreset(isDark) }

    // MaterialExpressiveTheme 在 material3 1.4 里还是 internal；expressive 语义由
    // 自建 md3e 组件（花形/按压 morph/自绘 wavy）承载，主题入口用 MaterialTheme。
    MaterialTheme(
        colorScheme = colorScheme,
        typography = AppTypography,
    ) {
        // 基于设计基准宽度 392dp（Pixel 7 中型手机）做等比密度缩放
        // 小屏设备 dp 值自动缩小，大屏设备保持不变（不放大）
        val configuration = LocalConfiguration.current
        val systemDensity = LocalDensity.current
        val screenWidthDp = configuration.screenWidthDp.toFloat()
        val screenHeightDp = configuration.screenHeightDp.toFloat()
        val isLandscape = screenWidthDp > screenHeightDp
        val designWidthDp = if (isLandscape) 780f else 420f
        val scaledDensity = remember(screenWidthDp, screenHeightDp, systemDensity) {
            if (screenWidthDp < designWidthDp) {
                val scale = screenWidthDp / designWidthDp
                Density(
                    density = systemDensity.density * scale,
                    fontScale = systemDensity.fontScale,
                )
            } else {
                systemDensity
            }
        }

        CompositionLocalProvider(
            LocalExtendedColors provides extendedColors,
            LocalDensity provides scaledDensity,
            LocalIsDarkTheme provides isDark,
            LocalProgressBarStyle provides config.progressBarStyle,
        ) {
        // 同步 window 背景色，防止深色模式切换时闪白
        val view = LocalView.current
        SideEffect {
            val window = (view.context as? Activity)?.window ?: return@SideEffect
            window.decorView.setBackgroundColor(colorScheme.surface.toArgb())
        }
        content()
        }
    }
}
