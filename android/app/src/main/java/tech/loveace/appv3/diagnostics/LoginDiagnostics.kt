package tech.loveace.appv3.diagnostics

import android.content.Context
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import tech.loveace.appv3.data.model.ECLoginStatus
import tech.loveace.appv3.data.model.UAAPLoginStatus

/**
 * 一次 HTTP 往返的原始信息，由 HttpClient 传入；在 [LoginDiagnostics] 中遮挡和压缩后才写入日志。
 * 请求头、请求体、响应头、响应体只用于生成摘要，都不会被原样保存。
 */
data class HttpRecord(
    val method: String,
    val url: String?,
    val status: Int?,
    val durationMs: Long,
    val requestHeaders: Map<String, String>,
    val requestBody: ByteArray?,
    val responseHeaders: Map<String, String>,
    val responseBody: ByteArray?,
    val error: String?,
)

/**
 * 登录诊断：保留最近 10 次登录的详细调试日志，格式参考 PCL 的调试日志。
 * 与 iOS `LoginDiagnostics`（`ios/loveaceios/Network/LoginDiagnostics.swift`）逐函数对应。
 *
 * 遮挡规则：
 * - 敏感字段的值统一写成 `<字段名驼峰形式>`，例如 `password` → `<Password>`。
 * - 非常规请求头保留首尾各两位，中间用 `***` 代替；学号保留首尾各两位。
 * - 图片和其他二进制只记录字节数，不记录内容。
 */
object LoginDiagnostics {
    const val MAX_ATTEMPTS = 10
    const val MAX_STEPS = 300
    const val EXCERPT_LIMIT = 800

    private const val DIR_NAME = "login_diagnostics"
    private const val FILE_NAME = "attempts.json"

    @Serializable
    enum class Outcome(val label: String, val isFailure: Boolean) {
        SUCCESS("成功", false),
        INVALID_CREDENTIALS("账号或密码错误", true),
        CAPTCHA_REQUIRED("等待输入验证码", false),
        CAPTCHA_INVALID("验证码错误", true),
        PASSWORD_CHANGE_REQUIRED("学校要求修改密码", true),
        NETWORK("网络连接失败", true),
        OTHER("登录失败（其他原因）", true),
        CANCELLED("已取消（被新的登录替换）", true),
        UNFINISHED("未完成", false),
    }

    enum class LogLevel { INFO, WARN, ERROR, RESULT }

    enum class LogModule { AUTH, EC, UAAP, HTTP, RESULT }

    @Serializable
    data class Attempt(
        val id: String,
        val startedAt: Long,
        var endedAt: Long? = null,
        val account: String,
        val mode: String,
        var outcome: Outcome,
        var message: String? = null,
        val steps: MutableList<String> = mutableListOf(),
        var httpCount: Int = 0,
    )

    private val lock = Any()
    private val json = Json { ignoreUnknownKeys = true }
    private val listSerializer = ListSerializer(Attempt.serializer())
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val writeMutex = Mutex()

    // 以下字段均由 lock 保护
    private val attempts = mutableListOf<Attempt>()
    private var activeId: String? = null

    @Volatile private var file: File? = null

    /** 应用启动时调用一次：载入 `filesDir/login_diagnostics/attempts.json`（若存在） */
    fun init(context: Context) {
        synchronized(lock) {
            if (file != null) return
            val directory = File(context.applicationContext.filesDir, DIR_NAME)
            directory.mkdirs()
            val target = File(directory, FILE_NAME)
            file = target
            attempts.clear()
            attempts.addAll(readAttempts(target).takeLast(MAX_ATTEMPTS))
        }
    }

    /** 是否存在失败记录（决定登录页是否显示分享按钮） */
    fun hasFailureRecords(): Boolean = synchronized(lock) {
        attempts.any { it.outcome.isFailure }
    }

    /** 当前保存的登录次数（最多 [MAX_ATTEMPTS]） */
    fun attemptCount(): Int = synchronized(lock) { attempts.size }

    /** 当前保存的登录记录副本，按时间顺序（旧的在前） */
    fun savedAttempts(): List<Attempt> = snapshot()

    /** 是否有进行中的登录尝试。HttpClient 只在此时才组装 HTTP 记录。 */
    fun isRecording(): Boolean = synchronized(lock) { activeId != null }

    /** 开始一次登录。上一次还没结束的尝试被记为已取消；只保留最近 [MAX_ATTEMPTS] 次。 */
    fun beginAttempt(id: String, userId: String, mode: String) {
        val now = System.currentTimeMillis()
        synchronized(lock) {
            activeId?.let { previousId ->
                attempts.firstOrNull { it.id == previousId && it.endedAt == null }?.let { previous ->
                    previous.outcome = Outcome.CANCELLED
                    previous.endedAt = now
                    appendStep(previous, line(LogLevel.WARN, LogModule.AUTH, "被新的登录替换，上一次记为已取消", now))
                }
            }
            val attempt = Attempt(
                id = id,
                startedAt = now,
                account = maskAccount(userId),
                mode = mode,
                outcome = Outcome.UNFINISHED,
            )
            attempts.add(attempt)
            while (attempts.size > MAX_ATTEMPTS) attempts.removeAt(0)
            activeId = id
            appendStep(attempt, line(LogLevel.INFO, LogModule.AUTH, "开始登录 · 模式 $mode", now))
        }
        persist()
    }

    /** 记录一条脱敏后的步骤。每个尝试最多 [MAX_STEPS] 步。 */
    fun note(
        id: String,
        text: String,
        level: LogLevel = LogLevel.INFO,
        module: LogModule = LogModule.AUTH,
    ) {
        val step = line(level, module, LoginLogCompressor.text(text))
        val changed = synchronized(lock) {
            val attempt = attempts.firstOrNull { it.id == id }
            attempt != null && appendStep(attempt, step)
        }
        if (changed) persist()
    }

    /** 结束一次登录：写入结果、原因和结束行（结束行与其他步骤一样受 [MAX_STEPS] 限制，同 iOS）。 */
    fun finish(id: String, outcome: Outcome, message: String?) {
        val end = System.currentTimeMillis()
        val sanitized = message?.let { LoginLogCompressor.text(it) }
        val changed = synchronized(lock) {
            val attempt = attempts.firstOrNull { it.id == id }
            if (attempt == null) {
                false
            } else {
                attempt.outcome = outcome
                attempt.message = sanitized
                attempt.endedAt = end
                val seconds = (end - attempt.startedAt) / 1000.0
                val reason = sanitized?.let { "（$it）" } ?: ""
                val footer = "==== 结束：${outcome.label}$reason · 耗时 ${String.format(Locale.US, "%.1f", seconds)}s · HTTP ${attempt.httpCount} 次 ===="
                appendStep(attempt, footer)
                if (activeId == id) activeId = null
                true
            }
        }
        if (changed) persist()
    }

    /** 记录一次 HTTP 往返。只在登录进行中生效，其他时候直接忽略。 */
    fun recordHttp(record: HttpRecord) {
        if (!isRecording()) return
        val (level, text) = describeHttp(record)
        val changed = synchronized(lock) {
            val attempt = activeId?.let { id -> attempts.firstOrNull { it.id == id } }
            if (attempt == null) {
                false
            } else {
                attempt.httpCount += 1
                appendStep(attempt, line(level, LogModule.HTTP, text))
                true
            }
        }
        if (changed) persist()
    }

    /** EC 阶段的结果摘要：只记录是否存在，不记录任何值 */
    fun ecSummary(status: ECLoginStatus): String {
        val result = if (status.success) "成功" else "失败"
        return "EC 结果 $result " +
            "凭据错误=${yesNo(status.failInvalidCredentials)} " +
            "网络错误=${yesNo(status.failNetworkError)} " +
            "其他=${yesNo(status.failUnknownError)} " +
            "需要验证码=${yesNo(status.failCaptchaRequired)} " +
            "验证码错误=${yesNo(status.failCaptchaInvalid)} " +
            "twfid=${presence(status.failNotFoundTwfid)} " +
            "rsaKey=${presence(status.failNotFoundRsaKey)} " +
            "rsaExp=${presence(status.failNotFoundRsaExp)} " +
            "csrf=${presence(status.failNotFoundCsrfCode)}"
    }

    /** UAAP 阶段的结果摘要：只记录是否存在，不记录任何值 */
    fun uaapSummary(status: UAAPLoginStatus): String {
        val result = if (status.success) "成功" else "失败"
        return "UAAP 结果 $result " +
            "凭据错误=${yesNo(status.failInvalidCredentials)} " +
            "需改密=${yesNo(status.failPasswordChangeRequired)} " +
            "网络错误=${yesNo(status.failNetworkError)} " +
            "其他=${yesNo(status.failUnknownError)} " +
            "lt=${presence(status.failNotFoundLt)} " +
            "execution=${presence(status.failNotFoundExecution)}"
    }

    /** 字节数：小于 1 KB 显示 B，否则显示 KB（一位小数） */
    fun sizeText(bytes: Int): String =
        if (bytes < 1024) "${bytes}B" else String.format(Locale.US, "%.1fKB", bytes / 1024.0)

    // ==================== 内部实现 ====================

    /** 调用方必须持有 lock */
    private fun appendStep(attempt: Attempt, step: String): Boolean {
        if (attempt.steps.size >= MAX_STEPS) return false
        attempt.steps.add(step)
        return true
    }

    private fun snapshot(): List<Attempt> = synchronized(lock) {
        attempts.map { it.copy(steps = it.steps.toMutableList()) }
    }

    /**
     * 写盘在后台串行进行。每次写入都在互斥锁内读取最新快照，
     * 因此即使协程调度顺序与调用顺序不同，最终文件也一定是最新状态。
     */
    private fun persist() {
        val target = file ?: return
        scope.launch {
            writeMutex.withLock {
                val data = json.encodeToString(listSerializer, snapshot())
                runCatching {
                    val temp = File(target.parentFile, "${target.name}.tmp")
                    temp.writeText(data)
                    temp.renameTo(target)
                }
            }
        }
    }

    private fun readAttempts(target: File): List<Attempt> {
        if (!target.isFile) return emptyList()
        return try {
            json.decodeFromString(listSerializer, target.readText())
        } catch (_: Exception) {
            emptyList()
        }
    }

    /** 与 iOS `recordHTTP` 的块结构一致：第一行是 HTTP 摘要，后面是 `  │ ` 开头的请求头、请求体、响应行 */
    private fun describeHttp(record: HttpRecord): Pair<LogLevel, String> {
        val contentType = headerValue("Content-Type", record.responseHeaders)
        val head = mutableListOf("${record.method} ${LoginLogCompressor.url(record.url)}")
        head.add(record.status?.let { "→ $it" } ?: "→ 无响应")
        head.add("(${record.durationMs}ms)")
        contentType?.let { head.add("type=${LoginLogCompressor.mediaType(it)}") }
        record.responseBody?.let { head.add("len=${sizeText(it.size)}") }
        val headerLines = LoginLogCompressor.responseHeaderLines(record.responseHeaders)
        if (headerLines.isNotEmpty()) head.add("头[${headerLines.joinToString(",")}]")
        record.responseBody?.let { body ->
            val markers = LoginLogCompressor.markers(body)
            if (markers.isNotEmpty()) head.add("标记[${markers.joinToString("、")}]")
        }
        headerValue("Location", record.responseHeaders)
            ?.takeIf { it.isNotEmpty() }
            ?.let { head.add("跳转 ${LoginLogCompressor.url(it)}") }
        record.error?.let { head.add("错误 ${LoginLogCompressor.text(it)}") }

        val block = mutableListOf(head.joinToString(" "))
        val requestLines = LoginLogCompressor.requestHeaderLines(record.requestHeaders)
        if (requestLines.isNotEmpty()) block.add("  │ 请求头 " + requestLines.joinToString(" "))
        record.requestBody
            ?.takeIf { it.isNotEmpty() }
            ?.let { body ->
                val requestType = headerValue("Content-Type", record.requestHeaders)
                val summary = if (requestType?.contains("x-www-form-urlencoded", ignoreCase = true) == true) {
                    LoginLogCompressor.formSummary(body)
                } else {
                    LoginLogCompressor.excerpt(body, limit = EXCERPT_LIMIT)
                }
                block.add("  │ 请求体 $summary")
            }
        record.responseBody?.let { body ->
            if (LoginLogCompressor.isBinary(contentType)) {
                block.add("  │ 响应 二进制 ${sizeText(body.size)}（不记录内容）")
            } else {
                block.add("  │ 响应 " + LoginLogCompressor.excerpt(body))
            }
        }

        val level = when {
            record.error != null -> LogLevel.ERROR
            (record.status ?: 0) >= 400 -> LogLevel.WARN
            else -> LogLevel.INFO
        }
        return level to block.joinToString("\n")
    }

    /** 响应头取值（大小写不敏感） */
    private fun headerValue(name: String, headers: Map<String, String>): String? =
        headers.entries.firstOrNull { it.key.equals(name, ignoreCase = true) }?.value

    /** 日志行：`[HH:mm:ss.SSS] [LEVEL] [MODULE] 文本`，LEVEL 与 MODULE 各补齐到 5 个字符 */
    private fun line(level: LogLevel, module: LogModule, text: String, at: Long = System.currentTimeMillis()): String =
        "[${format(at, "HH:mm:ss.SSS")}] [${level.name.padEnd(5)}] [${module.name.padEnd(5)}] $text"

    private fun format(millis: Long, pattern: String): String =
        SimpleDateFormat(pattern, Locale.US).format(Date(millis))

    private fun maskAccount(userId: String): String =
        if (userId.length > 4) userId.take(2) + "****" + userId.takeLast(2) else "****"

    private fun yesNo(value: Boolean): String = if (value) "是" else "否"

    /** 存在为「有」，缺失为「缺」（`missing` 为 true 表示缺失） */
    private fun presence(missing: Boolean): String = if (missing) "缺" else "有"
}
