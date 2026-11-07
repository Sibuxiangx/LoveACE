package tech.loveace.appv3.data.local

import android.content.Context
import android.util.Log
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import tech.loveace.appv3.data.model.UserCredentials

/**
 * 加密凭证存储 - 使用 EncryptedSharedPreferences (AES-256)
 */
class CredentialStore(context: Context) {

    private val masterKey = MasterKey.Builder(context)
        .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
        .build()

    private val prefs = EncryptedSharedPreferences.create(
        context,
        "loveace_credentials",
        masterKey,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )

    fun save(credentials: UserCredentials) {
        prefs.edit()
            .putString(KEY_USER_ID, credentials.userId)
            .putString(KEY_EC_PASSWORD, credentials.ecPassword)
            .putString(KEY_PASSWORD, credentials.password)
            .apply()
    }

    fun load(): UserCredentials? = guardedRead<UserCredentials>("load") {
        val userId = prefs.getString(KEY_USER_ID, null) ?: return@guardedRead null
        val ecPassword = prefs.getString(KEY_EC_PASSWORD, null) ?: return@guardedRead null
        val password = prefs.getString(KEY_PASSWORD, null) ?: return@guardedRead null
        UserCredentials(userId, ecPassword, password)
    }

    fun clear() {
        prefs.edit()
            .remove(KEY_USER_ID)
            .remove(KEY_EC_PASSWORD)
            .remove(KEY_PASSWORD)
            .apply()
    }

    fun hasCredentials(): Boolean = guardedRead<Boolean>("hasCredentials") { prefs.contains(KEY_USER_ID) } ?: false

    // Remember password (separate from session credentials)
    fun saveRemembered(credentials: UserCredentials) {
        prefs.edit()
            .putString(KEY_REMEMBERED_USER_ID, credentials.userId)
            .putString(KEY_REMEMBERED_EC_PASSWORD, credentials.ecPassword)
            .putString(KEY_REMEMBERED_PASSWORD, credentials.password)
            .putBoolean(KEY_REMEMBER_ENABLED, true)
            .apply()
    }

    fun loadRemembered(): UserCredentials? = guardedRead<UserCredentials>("loadRemembered") {
        if (!prefs.getBoolean(KEY_REMEMBER_ENABLED, false)) return@guardedRead null
        val userId = prefs.getString(KEY_REMEMBERED_USER_ID, null) ?: return@guardedRead null
        val ecPassword = prefs.getString(KEY_REMEMBERED_EC_PASSWORD, null) ?: return@guardedRead null
        val password = prefs.getString(KEY_REMEMBERED_PASSWORD, null) ?: return@guardedRead null
        UserCredentials(userId, ecPassword, password)
    }

    fun clearRemembered() {
        prefs.edit()
            .remove(KEY_REMEMBERED_USER_ID)
            .remove(KEY_REMEMBERED_EC_PASSWORD)
            .remove(KEY_REMEMBERED_PASSWORD)
            .remove(KEY_REMEMBER_ENABLED)
            .apply()
    }

    /** 读取凭证：Keystore 或解密失败时返回 null，且不清除已保存的凭证 */
    private fun <T : Any> guardedRead(step: String, block: () -> T?): T? =
        try {
            block()
        } catch (e: Exception) {
            Log.w(TAG, "$step failed: ${e.javaClass.simpleName}")
            null
        }

    companion object {
        private const val TAG = "CredentialStore"
        private const val KEY_USER_ID = "user_id"
        private const val KEY_EC_PASSWORD = "ec_password"
        private const val KEY_PASSWORD = "password"
        private const val KEY_REMEMBERED_USER_ID = "remembered_user_id"
        private const val KEY_REMEMBERED_EC_PASSWORD = "remembered_ec_password"
        private const val KEY_REMEMBERED_PASSWORD = "remembered_password"
        private const val KEY_REMEMBER_ENABLED = "remember_password_enabled"
    }
}
