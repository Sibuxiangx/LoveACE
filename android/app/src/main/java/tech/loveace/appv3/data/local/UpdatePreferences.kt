package tech.loveace.appv3.data.local

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringSetPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.first

private val Context.updateDataStore: DataStore<Preferences> by preferencesDataStore(
    name = "update_prefs"
)

data class UpdatePreferenceState(
    val dismissedAnnouncementIds: Set<String> = emptySet(),
    val ignoredReleaseKeys: Set<String> = emptySet(),
)

class UpdatePreferences(private val context: Context) {
    private object Keys {
        val DISMISSED_ANNOUNCEMENTS = stringSetPreferencesKey("dismissed_announcement_ids")
        val IGNORED_RELEASES = stringSetPreferencesKey("ignored_release_keys")
    }

    suspend fun getState(): UpdatePreferenceState {
        val preferences = context.updateDataStore.data.first()
        return UpdatePreferenceState(
            dismissedAnnouncementIds = preferences[Keys.DISMISSED_ANNOUNCEMENTS].orEmpty(),
            ignoredReleaseKeys = preferences[Keys.IGNORED_RELEASES].orEmpty(),
        )
    }

    suspend fun dismissAnnouncement(id: String) {
        context.updateDataStore.edit { preferences ->
            preferences[Keys.DISMISSED_ANNOUNCEMENTS] =
                preferences[Keys.DISMISSED_ANNOUNCEMENTS].orEmpty() + id
        }
    }

    suspend fun ignoreRelease(key: String) {
        context.updateDataStore.edit { preferences ->
            preferences[Keys.IGNORED_RELEASES] =
                preferences[Keys.IGNORED_RELEASES].orEmpty() + key
        }
    }
}
