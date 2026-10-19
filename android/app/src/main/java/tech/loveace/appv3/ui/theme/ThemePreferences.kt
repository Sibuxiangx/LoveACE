package tech.loveace.appv3.ui.theme

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.*
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.themeDataStore: DataStore<Preferences> by preferencesDataStore(name = "theme_prefs")

data class ThemeConfig(
    val presetId: String = ThemePresets.DEFAULT.id,
    val darkMode: DarkMode = DarkMode.SYSTEM,
    val useDynamicColor: Boolean = false,
    val courseNotificationEnabled: Boolean = false,
)

enum class DarkMode { SYSTEM, LIGHT, DARK }

class ThemePreferences(private val context: Context) {

    private object Keys {
        val PRESET_ID = stringPreferencesKey("theme_preset_id")
        /** 旧版按 ARGB 存的种子色，读取后迁移为预设 id */
        val SEED_COLOR_LEGACY = intPreferencesKey("seed_color_argb")
        val DARK_MODE = stringPreferencesKey("dark_mode")
        val DYNAMIC_COLOR = booleanPreferencesKey("dynamic_color")
        val COURSE_NOTIFICATION = booleanPreferencesKey("course_notification")
    }

    val themeConfig: Flow<ThemeConfig> = context.themeDataStore.data.map { prefs ->
        val legacySeed = prefs[Keys.SEED_COLOR_LEGACY]
        val presetId = prefs[Keys.PRESET_ID]
            ?: legacySeed?.let { ThemePresets.migrateLegacySeed(it) }
            ?: ThemePresets.DEFAULT.id
        ThemeConfig(
            presetId = presetId,
            darkMode = try { DarkMode.valueOf(prefs[Keys.DARK_MODE] ?: "SYSTEM") } catch (_: Exception) { DarkMode.SYSTEM },
            useDynamicColor = prefs[Keys.DYNAMIC_COLOR] ?: false,
            courseNotificationEnabled = prefs[Keys.COURSE_NOTIFICATION] ?: false,
        )
    }

    suspend fun setPreset(presetId: String) {
        context.themeDataStore.edit { it[Keys.PRESET_ID] = presetId }
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
}
