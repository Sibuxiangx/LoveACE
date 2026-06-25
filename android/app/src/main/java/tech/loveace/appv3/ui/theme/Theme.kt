package tech.loveace.appv3.ui.theme

import android.app.Activity
import android.app.Application
import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.*
import androidx.compose.runtime.*
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

    fun setSeedColor(argb: Int) = viewModelScope.launch { prefs.setSeedColor(argb) }
    fun setDarkMode(mode: DarkMode) = viewModelScope.launch { prefs.setDarkMode(mode) }
    fun setDynamicColor(enabled: Boolean) = viewModelScope.launch { prefs.setDynamicColor(enabled) }
    fun setCourseNotification(enabled: Boolean) = viewModelScope.launch { prefs.setCourseNotification(enabled) }
    fun setProgressBarStyle(style: ProgressBarStyle) = viewModelScope.launch { prefs.setProgressBarStyle(style) }
}

/**
 * 根据种子色生成 M3 配色方案，surface 系列颜色带有种子色色调
 */
private fun generateColorScheme(seedArgb: Int, isDark: Boolean): ColorScheme {
    val seed = Color(seedArgb)
    val hsl = colorToHsl(seed)
    val h = hsl[0]; val s = hsl[1]

    return if (isDark) {
        darkColorScheme(
            primary = hslToColor(h, (s * 0.8f).coerceIn(0f, 1f), 0.75f),
            onPrimary = hslToColor(h, s, 0.15f),
            primaryContainer = hslToColor(h, (s * 0.9f).coerceIn(0f, 1f), 0.30f),
            onPrimaryContainer = hslToColor(h, (s * 0.6f).coerceIn(0f, 1f), 0.90f),
            secondary = hslToColor((h + 30f) % 360f, (s * 0.5f).coerceIn(0f, 1f), 0.75f),
            onSecondary = hslToColor((h + 30f) % 360f, (s * 0.4f).coerceIn(0f, 1f), 0.15f),
            secondaryContainer = hslToColor((h + 30f) % 360f, (s * 0.4f).coerceIn(0f, 1f), 0.25f),
            onSecondaryContainer = hslToColor((h + 30f) % 360f, (s * 0.3f).coerceIn(0f, 1f), 0.90f),
            tertiary = hslToColor((h + 60f) % 360f, (s * 0.6f).coerceIn(0f, 1f), 0.75f),
            onTertiary = hslToColor((h + 60f) % 360f, (s * 0.5f).coerceIn(0f, 1f), 0.15f),
            tertiaryContainer = hslToColor((h + 60f) % 360f, (s * 0.5f).coerceIn(0f, 1f), 0.25f),
            onTertiaryContainer = hslToColor((h + 60f) % 360f, (s * 0.4f).coerceIn(0f, 1f), 0.90f),
            error = Color(0xFFFFB4AB),
            onError = Color(0xFF690005),
            errorContainer = Color(0xFF93000A),
            onErrorContainer = Color(0xFFFFDAD6),
            background = hslToColor(h, (s * 0.10f).coerceIn(0f, 1f), 0.08f),
            onBackground = Color(0xFFE5E1E9),
            surface = hslToColor(h, (s * 0.10f).coerceIn(0f, 1f), 0.08f),
            onSurface = Color(0xFFE5E1E9),
            onSurfaceVariant = Color(0xFFC7C5D0),
            outline = Color(0xFF918F9A),
            outlineVariant = hslToColor(h, (s * 0.10f).coerceIn(0f, 1f), 0.25f),
            surfaceDim = hslToColor(h, (s * 0.08f).coerceIn(0f, 1f), 0.06f),
            surfaceBright = hslToColor(h, (s * 0.10f).coerceIn(0f, 1f), 0.22f),
            surfaceContainerLowest = hslToColor(h, (s * 0.08f).coerceIn(0f, 1f), 0.04f),
            surfaceContainerLow = hslToColor(h, (s * 0.10f).coerceIn(0f, 1f), 0.10f),
            surfaceContainer = hslToColor(h, (s * 0.10f).coerceIn(0f, 1f), 0.13f),
            surfaceContainerHigh = hslToColor(h, (s * 0.10f).coerceIn(0f, 1f), 0.16f),
            surfaceContainerHighest = hslToColor(h, (s * 0.10f).coerceIn(0f, 1f), 0.20f),
            inverseSurface = hslToColor(h, (s * 0.10f).coerceIn(0f, 1f), 0.90f),
            inverseOnSurface = hslToColor(h, (s * 0.08f).coerceIn(0f, 1f), 0.18f),
            inversePrimary = hslToColor(h, s, 0.42f),
        )
    } else {
        lightColorScheme(
            primary = hslToColor(h, s, 0.42f),
            onPrimary = Color.White,
            primaryContainer = hslToColor(h, (s * 0.7f).coerceIn(0f, 1f), 0.90f),
            onPrimaryContainer = hslToColor(h, s, 0.12f),
            secondary = hslToColor((h + 30f) % 360f, (s * 0.4f).coerceIn(0f, 1f), 0.40f),
            onSecondary = Color.White,
            secondaryContainer = hslToColor((h + 30f) % 360f, (s * 0.4f).coerceIn(0f, 1f), 0.90f),
            onSecondaryContainer = hslToColor((h + 30f) % 360f, (s * 0.3f).coerceIn(0f, 1f), 0.12f),
            tertiary = hslToColor((h + 60f) % 360f, (s * 0.5f).coerceIn(0f, 1f), 0.38f),
            onTertiary = Color.White,
            tertiaryContainer = hslToColor((h + 60f) % 360f, (s * 0.5f).coerceIn(0f, 1f), 0.90f),
            onTertiaryContainer = hslToColor((h + 60f) % 360f, (s * 0.4f).coerceIn(0f, 1f), 0.12f),
            error = Color(0xFFBA1A1A),
            onError = Color.White,
            errorContainer = Color(0xFFFFDAD6),
            onErrorContainer = Color(0xFF410002),
            // 关键：background 和 surface 带有种子色色调，让整个 app 背景受主题色影响
            background = hslToColor(h, (s * 0.18f).coerceIn(0f, 1f), 0.97f),
            onBackground = Color(0xFF1C1B20),
            surface = hslToColor(h, (s * 0.18f).coerceIn(0f, 1f), 0.97f),
            onSurface = Color(0xFF1C1B20),
            onSurfaceVariant = Color(0xFF46464F),
            outline = Color(0xFF777680),
            outlineVariant = hslToColor(h, (s * 0.15f).coerceIn(0f, 1f), 0.82f),
            surfaceDim = hslToColor(h, (s * 0.15f).coerceIn(0f, 1f), 0.88f),
            surfaceBright = hslToColor(h, (s * 0.18f).coerceIn(0f, 1f), 0.98f),
            surfaceContainerLowest = Color.White,
            surfaceContainerLow = hslToColor(h, (s * 0.18f).coerceIn(0f, 1f), 0.95f),
            surfaceContainer = hslToColor(h, (s * 0.16f).coerceIn(0f, 1f), 0.93f),
            surfaceContainerHigh = hslToColor(h, (s * 0.14f).coerceIn(0f, 1f), 0.91f),
            surfaceContainerHighest = hslToColor(h, (s * 0.12f).coerceIn(0f, 1f), 0.89f),
            inverseSurface = Color(0xFF313036),
            inverseOnSurface = hslToColor(h, (s * 0.12f).coerceIn(0f, 1f), 0.95f),
            inversePrimary = hslToColor(h, (s * 0.8f).coerceIn(0f, 1f), 0.75f),
        )
    }
}

/** RGB → HSL */
private fun colorToHsl(color: Color): FloatArray {
    val r = color.red; val g = color.green; val b = color.blue
    val max = maxOf(r, g, b); val min = minOf(r, g, b)
    val l = (max + min) / 2f
    if (max == min) return floatArrayOf(0f, 0f, l)
    val d = max - min
    val s = if (l > 0.5f) d / (2f - max - min) else d / (max + min)
    val h = when (max) {
        r -> ((g - b) / d + (if (g < b) 6f else 0f)) * 60f
        g -> ((b - r) / d + 2f) * 60f
        else -> ((r - g) / d + 4f) * 60f
    }
    return floatArrayOf(h, s, l)
}

/** HSL → Color */
private fun hslToColor(h: Float, s: Float, l: Float): Color {
    if (s == 0f) return Color(l, l, l)
    val q = if (l < 0.5f) l * (1f + s) else l + s - l * s
    val p = 2f * l - q
    fun hue2rgb(t: Float): Float {
        val tt = when { t < 0f -> t + 1f; t > 1f -> t - 1f; else -> t }
        return when {
            tt < 1f / 6f -> p + (q - p) * 6f * tt
            tt < 1f / 2f -> q
            tt < 2f / 3f -> p + (q - p) * (2f / 3f - tt) * 6f
            else -> p
        }
    }
    val hNorm = h / 360f
    return Color(hue2rgb(hNorm + 1f / 3f), hue2rgb(hNorm), hue2rgb(hNorm - 1f / 3f))
}

@OptIn(ExperimentalMaterial3ExpressiveApi::class)
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

    val colorScheme = when {
        config.useDynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (isDark) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }
        else -> generateColorScheme(config.seedColorArgb, isDark)
    }

    MaterialExpressiveTheme(
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
