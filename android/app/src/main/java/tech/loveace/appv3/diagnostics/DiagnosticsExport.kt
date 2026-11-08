package tech.loveace.appv3.diagnostics

import android.os.Build
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import tech.loveace.appv3.BuildConfig
import tech.loveace.appv3.diagnostics.LoginDiagnostics.Attempt
import tech.loveace.appv3.diagnostics.LoginDiagnostics.Outcome

/**
 * 把保存的登录记录导出为 `loveace.login-diagnostics/v1` 的 diagnostic.json（契约第 2 节）。
 * 对象键按字典序排列；只输出契约规定的键；超过契约长度上限的字符串在这里截断。
 */
object DiagnosticsExport {
    const val SCHEMA = "loveace.login-diagnostics/v1"

    private const val MAX_LINE_CHARS = 4000
    private const val MAX_MESSAGE_CHARS = 500
    private const val MAX_ACCOUNT_CHARS = 16
    private const val MAX_MODE_CHARS = 16
    private const val MAX_HTTP_COUNT = 10_000

    /** 生成 diagnostic.json 的 UTF-8 文本。[attempts] 应为 1 到 10 条。 */
    fun build(attempts: List<Attempt>, nowMillis: Long): String {
        val root = obj(
            "schema" to str(SCHEMA),
            "createdAt" to str(iso(nowMillis)),
            "app" to obj(
                "platform" to str("android"),
                "version" to str(BuildConfig.VERSION_NAME.take(20)),
                "build" to str(BuildConfig.VERSION_CODE.toString().take(20)),
            ),
            "device" to obj(
                "model" to str(Build.MODEL.orEmpty().take(64)),
                "os" to str("Android"),
                "osVersion" to str(Build.VERSION.RELEASE.orEmpty().take(32)),
                "timezone" to str(timezoneOffset(nowMillis)),
                "locale" to str(Locale.getDefault().toLanguageTag().take(32)),
            ),
            "attempts" to JsonArray(attempts.map { attempt(it) }),
        )
        return Json.encodeToString(JsonElement.serializer(), root)
    }

    private fun attempt(attempt: Attempt): JsonObject = obj(
        "id" to str(attempt.id),
        "startedAt" to str(iso(attempt.startedAt)),
        "endedAt" to (attempt.endedAt?.let { str(iso(it)) } ?: JsonNull),
        "account" to str(attempt.account.take(MAX_ACCOUNT_CHARS)),
        "mode" to str(attempt.mode.take(MAX_MODE_CHARS)),
        "outcome" to str(outcomeName(attempt.outcome)),
        "message" to (attempt.message?.let { str(it.take(MAX_MESSAGE_CHARS)) } ?: JsonNull),
        "httpCount" to JsonPrimitive(attempt.httpCount.coerceIn(0, MAX_HTTP_COUNT)),
        "lines" to JsonArray(attempt.steps.map { str(it.take(MAX_LINE_CHARS)) }),
    )

    private fun outcomeName(outcome: Outcome): String = when (outcome) {
        Outcome.SUCCESS -> "success"
        Outcome.INVALID_CREDENTIALS -> "invalidCredentials"
        Outcome.CAPTCHA_REQUIRED -> "captchaRequired"
        Outcome.CAPTCHA_INVALID -> "captchaInvalid"
        Outcome.PASSWORD_CHANGE_REQUIRED -> "passwordChangeRequired"
        Outcome.NETWORK -> "network"
        Outcome.OTHER -> "other"
        Outcome.CANCELLED -> "cancelled"
        Outcome.UNFINISHED -> "unfinished"
    }

    /** 键按字典序排列的对象 */
    private fun obj(vararg entries: Pair<String, JsonElement>): JsonObject =
        JsonObject(entries.toMap().toSortedMap())

    private fun str(value: String): JsonPrimitive = JsonPrimitive(value)

    /** ISO8601，带时区偏移，例如 2026-11-08T14:20:00+08:00 */
    private fun iso(millis: Long): String =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX", Locale.US).format(Date(millis))

    /** 时区偏移，例如 +08:00 */
    private fun timezoneOffset(millis: Long): String {
        val minutes = TimeZone.getDefault().getOffset(millis) / 60_000
        val sign = if (minutes >= 0) "+" else "-"
        val absolute = kotlin.math.abs(minutes)
        return String.format(Locale.US, "%s%02d:%02d", sign, absolute / 60, absolute % 60)
    }
}
