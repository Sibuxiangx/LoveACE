package tech.loveace.appv3.ui.theme

import android.content.Context
import androidx.compose.ui.graphics.Color
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.*
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.themeDataStore: DataStore<Preferences> by preferencesDataStore(name = "theme_prefs")

enum class ProgressBarStyle { WAVY, STANDARD }

data class ThemeConfig(
    val seedColorArgb: Int = SeedColors.DEFAULT.argb,
    val darkMode: DarkMode = DarkMode.SYSTEM,
    val useDynamicColor: Boolean = false,
    val courseNotificationEnabled: Boolean = false,
    val progressBarStyle: ProgressBarStyle = ProgressBarStyle.WAVY,
)

enum class DarkMode { SYSTEM, LIGHT, DARK }

data class SeedColorOption(
    val name: String,
    val color: Color,
    val argb: Int,
)

object SeedColors {
    val RIBBON_PURPLE = SeedColorOption("彩带紫", Color(0xFF5B5FE6), 0xFF5B5FE6.toInt())
    val OCEAN_BLUE = SeedColorOption("海洋蓝", Color(0xFF1976D2), 0xFF1976D2.toInt())
    val FOREST_GREEN = SeedColorOption("森林绿", Color(0xFF2E7D32), 0xFF2E7D32.toInt())
    val SUNSET_ORANGE = SeedColorOption("日落橙", Color(0xFFE65100), 0xFFE65100.toInt())
    val SAKURA_PINK = SeedColorOption("樱花粉", Color(0xFFD81B60), 0xFFD81B60.toInt())
    val AMBER_GOLD = SeedColorOption("琥珀金", Color(0xFFF9A825), 0xFFF9A825.toInt())
    val TEAL = SeedColorOption("青碧", Color(0xFF00897B), 0xFF00897B.toInt())
    val LAVENDER = SeedColorOption("薰衣草", Color(0xFF7E57C2), 0xFF7E57C2.toInt())
    val CORAL_RED = SeedColorOption("珊瑚红", Color(0xFFE53935), 0xFFE53935.toInt())
    val SLATE_BLUE = SeedColorOption("石板蓝", Color(0xFF546E7A), 0xFF546E7A.toInt())

    val DEFAULT = RIBBON_PURPLE

    val ALL = listOf(
        RIBBON_PURPLE, OCEAN_BLUE, FOREST_GREEN, SUNSET_ORANGE, SAKURA_PINK,
        AMBER_GOLD, TEAL, LAVENDER, CORAL_RED, SLATE_BLUE,
    )
}

class ThemePreferences(private val context: Context) {

    private object Keys {
        val SEED_COLOR = intPreferencesKey("seed_color_argb")
        val DARK_MODE = stringPreferencesKey("dark_mode")
        val DYNAMIC_COLOR = booleanPreferencesKey("dynamic_color")
        val COURSE_NOTIFICATION = booleanPreferencesKey("course_notification")
        val PROGRESS_BAR_STYLE = stringPreferencesKey("progress_bar_style")
    }

    val themeConfig: Flow<ThemeConfig> = context.themeDataStore.data.map { prefs ->
        ThemeConfig(
            seedColorArgb = prefs[Keys.SEED_COLOR] ?: SeedColors.DEFAULT.argb,
            darkMode = try { DarkMode.valueOf(prefs[Keys.DARK_MODE] ?: "SYSTEM") } catch (_: Exception) { DarkMode.SYSTEM },
            useDynamicColor = prefs[Keys.DYNAMIC_COLOR] ?: false,
            courseNotificationEnabled = prefs[Keys.COURSE_NOTIFICATION] ?: false,
            progressBarStyle = try { ProgressBarStyle.valueOf(prefs[Keys.PROGRESS_BAR_STYLE] ?: "WAVY") } catch (_: Exception) { ProgressBarStyle.WAVY },
        )
    }

    suspend fun setSeedColor(argb: Int) {
        context.themeDataStore.edit { it[Keys.SEED_COLOR] = argb }
    }

    suspend fun setDarkMode(mode: DarkMode) {
        context.themeDataStore.edit { it[Keys.DARK_MODE] = mode.name }
    }

    suspend fun setDynamicColor(enabled: Boolean) {
        context.themeDataStore.edit { it[Keys.DYNAMIC_COLOR] = enabled }
    }

    suspend fun setCourseNotification(enabled: Boolean) {
        context.themeDataStore.edit { it[Keys.COURSE_NOTIFICATION] = enabled }
    }

    suspend fun setProgressBarStyle(style: ProgressBarStyle) {
        context.themeDataStore.edit { it[Keys.PROGRESS_BAR_STYLE] = style.name }
    }
}
