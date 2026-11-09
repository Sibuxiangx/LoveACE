package tech.loveace.appv3.diagnostics

import java.net.URLDecoder
import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.Charset
import java.nio.charset.CodingErrorAction

/**
 * 把请求地址、正文、请求头、错误文本压缩并遮挡成短的、不含敏感信息的形式。
 * 与 iOS `LoginLogCompressor`（`ios/loveaceios/Network/LoginDiagnostics.swift`）逐函数对应。
 */
object LoginLogCompressor {
    private const val VPN_HOST = "vpn2.aufe.edu.cn"
    private const val VPN_SUFFIX = ".vpn2.aufe.edu.cn"
    private const val NO_ADDRESS = "[无地址]"

    private val markerTable: List<Pair<String, List<String>>> = listOf(
        "密码错误" to listOf("密码输入错误", "用户名或密码错误", "账号或密码错误"),
        "验证码" to listOf("rand_code", "RndImg", "验证码"),
        "改密" to listOf("completeInfo", "修改密码", "password/change"),
        "票据" to listOf("TGT-", "ticket="),
        "登录表单" to listOf("name=\"lt\"", "name=\"execution\"", "name='lt'", "name='execution'"),
        "会话失效" to listOf("会话已过期", "登录超时", "sdp-app-session"),
    )

    /** 标准请求头：值照常记录（Referer 和 Origin 仍压缩为服务名） */
    private val standardRequestHeaders = setOf(
        "accept", "accept-encoding", "accept-language", "content-type", "content-length", "connection",
        "host", "user-agent", "cache-control", "pragma", "origin", "referer", "upgrade-insecure-requests", "dnt",
    )

    /** 账号类字段：学号只保留首尾两位 */
    private val accountKeys = setOf("xh", "userid", "openid", "account", "studentid", "username", "loginname")

    /** 与 iOS `NetworkLogRedactor.isSensitive` 一致（不含 lt / execution / rand，它们只做精确匹配） */
    private val sensitiveNames = listOf(
        "authorization", "cookie", "set-cookie", "password", "passwd", "token", "ticket", "csrf",
        "secret", "credential", "jessionid", "jsessionid", "twfid", "username", "session", "svpn_name", "svpn_password",
    )
    private val sensitiveSubstrings = listOf("pwd", "captcha", "validatecode", "rsa", "sign", "secret", "cookie")

    private val gb18030: Charset? = runCatching { Charset.forName("GB18030") }.getOrNull()

    private val urlPattern = Regex("""https?://[^\s"'<>,，。；;]+""")
    private val digitRunPattern = Regex("""(?<!\d)\d{8,12}(?!\d)""")
    private val nonLetterOrDigitPattern = Regex("""[^\p{L}\p{N}]+""")
    private val unicodeWhitespacePattern = Regex("""\s+""")
    private val inputTagPattern = Regex("""(?i)<input[^>]*>""")
    private val hiddenTypePattern = Regex("""(?i)type=["']?hidden""")
    private val inputNamePattern = Regex("""(?i)name=["']?([A-Za-z0-9_\-]+)""")
    private val namePrefixPattern = Regex("""(?i)name=["']?""")
    private val inputValuePattern = Regex("""(?i)(value=["'])([^"']*)""")
    private val inputNameValuePattern = Regex("""(?i)(name=["']?)([A-Za-z0-9_\-]+)(["']?[^>]*?value=["'])([^"']*)""")
    private val keyValuePattern = Regex("""([A-Za-z0-9_\-]+)(["']?\s*[=:]\s*["']?)([^&\s,;<>"'{}\[\]]+)""")
    private val xmlSecretPattern = Regex("""(?i)(<((?:twfid|jsessionid|token|password|passwd|pwd|cookie|ticket))\b[^>]*>)[^<]+""")

    private class ParsedUrl(val host: String, val path: String, val queryCount: Int)

    // MARK: - 地址

    /** `http://uaap-aufe-edu-cn.vpn2.aufe.edu.cn/cas/login?service=…` -> `[uaap]/cas/login?×1` */
    fun url(url: String?): String {
        val parsed = url?.let { parseUrl(it) } ?: return NO_ADDRESS
        val segments = parsed.path
            .split('/')
            .filter { it.isNotEmpty() }
            .take(2)
            .map { segmentToken(percentDecode(it)) }
        val path = if (segments.isEmpty()) "" else "/" + segments.joinToString("/")
        val query = if (parsed.queryCount > 0) "?×${parsed.queryCount}" else ""
        return "[${serviceToken(parsed.host)}]$path$query"
    }

    /** 服务名：vpn 网关记为 vpn，`<服务>.vpn2.aufe.edu.cn` 取服务名，其他外部域名记为 ext:<首段> */
    fun serviceToken(host: String): String {
        if (host == VPN_HOST) return "vpn"
        if (host.endsWith(VPN_SUFFIX)) {
            val label = host.dropLast(VPN_SUFFIX.length)
            val parts = label.split('-').filter { it.isNotEmpty() }
            val first = parts.firstOrNull() ?: return "vpn"
            if (first.all { it.isDigit() }) return "ip"
            if (first == "api" && parts.size > 1) return "api-${parts[1]}"
            return first
        }
        val firstLabel = host.split('.').firstOrNull { it.isNotEmpty() } ?: host
        return "ext:$firstLabel"
    }

    /** 路径段：过长、带等号或纯数字的（通常是票据或 ID）替换为 * */
    fun segmentToken(segment: String): String {
        val count = segment.codePointCount(0, segment.length)
        if (count > 20 || segment.contains('=')) return "*"
        if (count >= 8 && segment.all { it.isDigit() }) return "*"
        return segment
    }

    // MARK: - 遮挡

    /** 敏感字段名统一写成 `<字段名驼峰形式>`，例如 `password` → `<Password>`，`Set-Cookie` → `<SetCookie>` */
    fun maskToken(key: String): String {
        val name = key
            .split(nonLetterOrDigitPattern)
            .filter { it.isNotEmpty() }
            .joinToString("") { word -> word.take(1).uppercase() + word.drop(1).lowercase() }
        return "<${name.ifEmpty { "Value" }}>"
    }

    fun isSensitiveKey(key: String): Boolean {
        if (isSensitiveName(key)) return true
        val lower = key.lowercase()
        return sensitiveSubstrings.any { lower.contains(it) }
    }

    /** 非常规值：长度不超过 6 时整体用 `***`，否则保留首尾各两位 */
    fun partialMask(value: String): String {
        if (value.length <= 6) return "***"
        return "${value.take(2)}***${value.takeLast(2)}"
    }

    /** 学号：至少 6 位纯数字时保留首尾两位，其余按 [partialMask] */
    fun studentIDMask(value: String): String {
        if (value.length < 6 || !value.all { it.isDigit() }) return partialMask(value)
        return "${value.take(2)}****${value.takeLast(2)}"
    }

    /** 8 到 12 位的数字串按学号规则遮挡 */
    fun maskDigitRuns(text: String): String =
        replaceMatches(text, digitRunPattern) { match -> studentIDMask(match.value) }

    /** 文本中的敏感键值：`name="x" … value="y"`、`key=value`、`key: value`、`"key":"value"` */
    fun maskSecrets(text: String): String {
        val inputsMasked = replaceMatches(text, inputNameValuePattern) { match ->
            val name = match.groupValues[2]
            if (!isSensitiveKey(name)) return@replaceMatches null
            match.groupValues[1] + name + match.groupValues[3] + maskToken(name)
        }
        val keyValueMasked = replaceMatches(inputsMasked, keyValuePattern) { match ->
            val key = match.groupValues[1]
            if (!isSensitiveKey(key)) return@replaceMatches null
            key + match.groupValues[2] + maskToken(key)
        }
        // XML 标签形式：<TwfID>值</TwfID> 的值替换为占位符，如 <TwfID><Twfid></TwfID>
        return replaceMatches(keyValueMasked, xmlSecretPattern) { match ->
            match.groupValues[1] + maskToken(match.groupValues[2])
        }
    }

    /** 隐藏域输入框的值替换为 `<字段名>`；没有 name 时用 `Hidden` */
    fun maskHiddenInputs(text: String): String =
        replaceMatches(text, inputTagPattern) { tagMatch ->
            val tag = tagMatch.value
            if (!hiddenTypePattern.containsMatchIn(tag)) return@replaceMatches null
            val name = inputNamePattern.find(tag)?.value?.let { namePrefixPattern.replace(it, "") } ?: "Hidden"
            replaceMatches(tag, inputValuePattern) { valueMatch ->
                valueMatch.groupValues[1] + maskToken(name)
            }
        }

    // MARK: - 请求与响应

    /** 请求头：Cookie、Authorization 和敏感字段用占位；标准请求头照常记录；其他非常规请求头首尾保留两位 */
    fun requestHeaderLines(headers: Map<String, String>): List<String> =
        headers.keys.sorted().map { name ->
            val value = headers[name].orEmpty()
            val lower = name.lowercase()
            when {
                lower == "cookie" || lower == "authorization" || isSensitiveKey(name) -> "$name=${maskToken(name)}"
                lower in standardRequestHeaders ->
                    if (lower == "referer" || lower == "origin") "$name=${url(value)}" else "$name=${text(value)}"
                else -> "$name=${partialMask(value)}"
            }
        }

    /** 响应头只列名字（前 12 个）；Set-Cookie 等敏感头给出占位。Content-Type 的值由调用方单独给出。 */
    fun responseHeaderLines(headers: Map<String, String>): List<String> =
        headers.keys.sorted().take(12).map { name ->
            if (name.lowercase() == "set-cookie" || isSensitiveKey(name)) "$name=${maskToken(name)}" else name
        }

    /** 表单请求体：键值成对列出（键值均已百分号解码）；敏感字段用占位，学号按学号规则遮挡；非表单正文走 [excerpt] */
    fun formSummary(data: ByteArray): String {
        val body = strictDecode(data, Charsets.UTF_8)
        if (body == null || !body.contains('=')) return excerpt(data)
        return body.split('&').filter { it.isNotEmpty() }.joinToString(" ") { pair ->
            val key = percentDecode(pair.substringBefore('='))
            val rawValue = if (pair.contains('=')) pair.substringAfter('=') else ""
            "$key=${displayValue(key, percentDecode(rawValue))}"
        }
    }

    fun displayValue(key: String, value: String): String {
        if (value.isEmpty()) return ""
        if (key.lowercase() in accountKeys) return studentIDMask(value)
        if (isSensitiveKey(key)) return maskToken(key)
        val cleaned = text(value)
        return if (cleaned.length > 60) cleaned.take(60) + "…" else cleaned
    }

    /** 响应正文摘要：压缩空白，压缩地址，遮挡隐藏域和敏感键值，学号按规则遮挡，超长截断 */
    fun excerpt(data: ByteArray, limit: Int = LoginDiagnostics.EXCERPT_LIMIT): String {
        val raw = decode(data) ?: return "（无法解码，${LoginDiagnostics.sizeText(data.size)}）"
        val flat = raw.split(unicodeWhitespacePattern).filter { it.isNotEmpty() }.joinToString(" ")
        val masked = maskDigitRuns(maskSecrets(maskHiddenInputs(urlsCompressed(flat))))
        if (masked.length > limit) {
            return "${masked.take(limit)}…（共 ${LoginDiagnostics.sizeText(data.size)}）"
        }
        return masked
    }

    /** 普通文本：先压缩地址，再遮挡敏感键值，最后遮挡学号 */
    fun text(raw: String): String = maskDigitRuns(maskSecrets(urlsCompressed(raw)))

    /** Content-Type 只保留媒体类型，去掉 charset 等参数 */
    fun mediaType(contentType: String): String = contentType.substringBefore(';').trim()

    fun isBinary(contentType: String?): Boolean {
        val type = contentType?.lowercase() ?: return false
        return type.startsWith("image/") || type.startsWith("audio/") || type.startsWith("video/") ||
            type.startsWith("application/octet-stream") || type.startsWith("application/pdf")
    }

    /** 正文关键词命中（只返回名称，不返回内容）。UTF-8 解码失败时回退到 GB18030。 */
    fun markers(body: ByteArray): List<String> {
        val text = decode(body) ?: return emptyList()
        return markerTable
            .filter { (_, keywords) -> keywords.any { text.contains(it) } }
            .map { it.first }
    }

    // MARK: - 工具

    private fun isSensitiveName(name: String): Boolean {
        val lower = name.lowercase().replace("-", "")
        if (lower == "lt" || lower == "execution" || lower == "rand") return true
        return sensitiveNames.any { lower.contains(it.replace("-", "")) }
    }

    private fun urlsCompressed(text: String): String =
        replaceMatches(text, urlPattern) { match -> url(match.value) }

    /** 用正则逐个替换：transform 返回 null 表示保持原样。从后往前替换，前面的下标保持有效。 */
    private fun replaceMatches(text: String, pattern: Regex, transform: (MatchResult) -> String?): String {
        val matches = pattern.findAll(text).toList()
        if (matches.isEmpty()) return text
        val result = StringBuilder(text)
        for (match in matches.asReversed()) {
            val replacement = transform(match) ?: continue
            result.replace(match.range.first, match.range.last + 1, replacement)
        }
        return result.toString()
    }

    /** 解析绝对地址或 `//host` 形式的地址；无法解析出主机时返回 null（对应 iOS 的 nil host） */
    private fun parseUrl(raw: String): ParsedUrl? {
        val noFragment = raw.substringBefore('#')
        val rest = if (noFragment.startsWith("//")) {
            noFragment.substring(2)
        } else {
            val schemeEnd = noFragment.indexOf("://")
            if (schemeEnd <= 0) return null
            val scheme = noFragment.substring(0, schemeEnd)
            if (!scheme.all { it.isLetterOrDigit() || it == '+' || it == '-' || it == '.' }) return null
            noFragment.substring(schemeEnd + 3)
        }
        val authorityEnd = rest.indexOfFirst { it == '/' || it == '?' }.let { if (it < 0) rest.length else it }
        val authority = rest.substring(0, authorityEnd)
        val afterAuthority = rest.substring(authorityEnd)
        val host = authority.substringAfterLast('@').substringBefore(':').lowercase()
        if (host.isEmpty()) return null
        val path = afterAuthority.substringBefore('?')
        val query = if (afterAuthority.contains('?')) afterAuthority.substringAfter('?') else ""
        val queryCount = query.split('&').count { it.isNotEmpty() }
        return ParsedUrl(host = host, path = path, queryCount = queryCount)
    }

    /** 百分号解码；`+` 保持原样（与 iOS `removingPercentEncoding` 一致）；无效编码返回原文 */
    private fun percentDecode(segment: String): String = try {
        URLDecoder.decode(segment.replace("+", "%2B"), "UTF-8")
    } catch (_: IllegalArgumentException) {
        segment
    }

    private fun decode(data: ByteArray): String? =
        strictDecode(data, Charsets.UTF_8) ?: gb18030?.let { strictDecode(data, it) }

    private fun strictDecode(data: ByteArray, charset: Charset): String? = try {
        charset.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
            .decode(ByteBuffer.wrap(data))
            .toString()
    } catch (_: CharacterCodingException) {
        null
    }
}
