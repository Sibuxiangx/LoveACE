package tech.loveace.appv3.analytics

import android.content.Context
import android.os.Build
import android.util.Log
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import tech.loveace.appv3.BuildConfig
import java.security.MessageDigest
import java.time.Instant
import java.util.UUID
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

object Analytics {
    private const val TAG = "Analytics"
    private const val PREFS = "loveace_analytics"
    private const val KEY_CLIENT_ID = "client_id"

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val client = OkHttpClient()
    private val jsonMediaType = "application/json; charset=utf-8".toMediaType()

    @Volatile private var appContext: Context? = null
    @Volatile private var clientId: String = ""
    @Volatile private var gradePrefix: String? = null
    @Volatile private var studentHash: String? = null

    fun init(context: Context) {
        if (appContext != null) return
        val applicationContext = context.applicationContext
        appContext = applicationContext
        val prefs = applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        clientId = prefs.getString(KEY_CLIENT_ID, null) ?: UUID.randomUUID().toString().also {
            prefs.edit().putString(KEY_CLIENT_ID, it).apply()
        }
    }

    fun setUser(userId: String) {
        gradePrefix = userId.take(4).takeIf { it.length == 4 && it.all { char -> char.isDigit() } }
        studentHash = if (BuildConfig.ANALYTICS_HASH_SALT.isNotBlank()) {
            md5(userId + BuildConfig.ANALYTICS_HASH_SALT)
        } else {
            null
        }
    }

    fun clearUser() {
        gradePrefix = null
        studentHash = null
    }

    fun trackAppStart(launchSource: String) = track("app_start", mapOf("launch_source" to launchSource))

    fun trackLoginSuccess(userId: String) {
        setUser(userId)
        track("login_success")
    }

    fun trackLoginFailed(userId: String, reason: String) {
        if (userId.isNotBlank()) setUser(userId)
        track("login_failed", mapOf("reason" to reason))
    }

    fun trackSessionExpired(reason: String) = track("session_expired", mapOf("reason" to reason))

    fun trackSessionReconnectSuccess() = track("session_reconnect_success", mapOf("result" to "success"))

    fun trackSessionReconnectFailed() = track("session_reconnect_failed", mapOf("result" to "failed"))

    fun trackScreen(screen: String) = track("screen_view", mapOf("screen" to screen))

    fun trackOtaCheck(result: String, currentVersion: String, latestVersion: String? = null) {
        val properties = mutableMapOf<String, Any?>(
            "result" to result,
            "current_version" to currentVersion,
        )
        latestVersion?.let { properties["latest_version"] = it }
        track("ota_check", properties)
    }

    fun trackOtaUpdateClick(currentVersion: String, targetVersion: String) {
        track("ota_update_click", mapOf("current_version" to currentVersion, "target_version" to targetVersion))
    }

    private fun track(name: String, properties: Map<String, Any?> = emptyMap()) {
        if (BuildConfig.ANALYTICS_ENDPOINT.isBlank() ||
            BuildConfig.ANALYTICS_API_KEY.isBlank() ||
            BuildConfig.ANALYTICS_SIGNING_SECRET.isBlank()
        ) return

        val payload = buildPayload(name, properties) ?: return
        scope.launch {
            runCatching { post(payload) }
                .onFailure { Log.d(TAG, "Analytics event dropped: ${it.message}") }
        }
    }

    private fun buildPayload(name: String, properties: Map<String, Any?>): String? {
        if (clientId.isBlank()) return null
        val event = JSONObject()
            .put("name", name)
            .put("time", Instant.now().toString())
            .put("properties", JSONObject().also { props ->
                properties.forEach { (key, value) ->
                    when (value) {
                        null -> props.put(key, JSONObject.NULL)
                        is String -> props.put(key, value)
                        is Number -> props.put(key, value)
                        is Boolean -> props.put(key, value)
                    }
                }
            })

        return JSONObject()
            .put("client_id", clientId)
            .put("platform", "android")
            .put("app_version", BuildConfig.VERSION_NAME)
            .put("build", BuildConfig.VERSION_CODE.toString())
            .put("os_version", Build.VERSION.RELEASE ?: "")
            .put("device_model", listOf(Build.MANUFACTURER, Build.MODEL).filter { !it.isNullOrBlank() }.joinToString(" "))
            .put("grade_prefix", gradePrefix ?: JSONObject.NULL)
            .put("student_hash", studentHash ?: JSONObject.NULL)
            .put("events", JSONArray().put(event))
            .toString()
    }

    private fun post(body: String) {
        val timestamp = (System.currentTimeMillis() / 1000).toString()
        val nonce = UUID.randomUUID().toString()
        val bodyHash = sha256(body)
        val signature = hmacSha256(BuildConfig.ANALYTICS_SIGNING_SECRET, "$timestamp.$nonce.$bodyHash")
        val request = Request.Builder()
            .url(BuildConfig.ANALYTICS_ENDPOINT)
            .header("Authorization", "Bearer ${BuildConfig.ANALYTICS_API_KEY}")
            .header("X-LoveACE-Timestamp", timestamp)
            .header("X-LoveACE-Nonce", nonce)
            .header("X-LoveACE-Signature", signature)
            .post(body.toRequestBody(jsonMediaType))
            .build()

        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) throw IllegalStateException("HTTP ${response.code}")
        }
    }

    private fun md5(value: String) = digest("MD5", value)

    private fun sha256(value: String) = digest("SHA-256", value)

    private fun digest(algorithm: String, value: String): String {
        val digest = MessageDigest.getInstance(algorithm).digest(value.toByteArray(Charsets.UTF_8))
        return digest.joinToString("") { "%02x".format(it) }
    }

    private fun hmacSha256(secret: String, message: String): String {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(secret.toByteArray(Charsets.UTF_8), "HmacSHA256"))
        return mac.doFinal(message.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
    }
}
