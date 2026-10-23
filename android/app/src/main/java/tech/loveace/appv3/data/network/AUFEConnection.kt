package tech.loveace.appv3.data.network

import android.util.Base64
import android.util.Log
import tech.loveace.appv3.data.model.ECLoginStatus
import tech.loveace.appv3.data.model.UAAPLoginStatus
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.bouncycastle.crypto.encodings.PKCS1Encoding
import org.bouncycastle.crypto.engines.DESedeEngine
import org.bouncycastle.crypto.engines.RSAEngine
import org.bouncycastle.crypto.paddings.PKCS7Padding
import org.bouncycastle.crypto.paddings.PaddedBufferedBlockCipher
import org.bouncycastle.crypto.params.KeyParameter
import org.bouncycastle.crypto.params.RSAKeyParameters
import java.math.BigInteger

/**
 * AUFE 教务系统连接器
 * 处理 EC(VPN) 和 UAAP(CAS) 双重认证
 */
class AUFEConnection(
    val userId: String,
    private val ecPassword: String,
    private val password: String,
) {
    lateinit var client: HttpClient
        private set
    lateinit var simpleClient: HttpClient
        private set
    lateinit var noRedirectClient: HttpClient
        private set

    var twfId: String? = null
        private set
    private var ecLogged = false
    private var uaapLogged = false

    /** 最近一次 reconnect() 中 UAAP 是否被学校强制改密拦截（用于停止自动重连并提示用户） */
    var lastUaapPasswordChangeRequired = false
        private set

    /** 最近一次 reconnect() 中 EC 是否要求输入验证码（自动重连无法人工输入，需回到登录页） */
    var lastEcCaptchaRequired = false
        private set

    /** EC 认证页解析结果（验证码上下文的一部分） */
    private class EcAuthPage(
        val twfId: String,
        val csrf: String,
        val rsaKey: String,
        val rsaExp: String,
        val rndImg: Boolean,
    )

    /** 获取验证码图片时保存的认证上下文；提交验证码后立即清空，不得复用 */
    private class PendingCaptcha(val page: EcAuthPage, val createdAt: Long)

    /** EC 认证页解析失败时抛出，由 [ecLogin] 转换为对应结果 */
    private class EcStepFailure(val status: ECLoginStatus) : Exception()

    private var pendingCaptcha: PendingCaptcha? = null

    fun startClient() {
        client = HttpClient(baseUrl = SERVER_URL, timeoutMs = TIMEOUT)
        simpleClient = HttpClient(baseUrl = SERVER_URL, timeoutMs = TIMEOUT)
        noRedirectClient = HttpClient(baseUrl = SERVER_URL, timeoutMs = TIMEOUT, followRedirects = false)
    }

    /** 设置 session 过期回调（所有 client 共享） */
    fun setOnSessionExpired(callback: () -> Unit) {
        client.onSessionExpired = callback
        simpleClient.onSessionExpired = callback
        // noRedirectClient 不设置，因为它本身就处理重定向
    }

    /** 心跳：轻量 GET 保持 VPN session 活跃 */
    fun heartbeat(): Boolean {
        return try {
            val response = client.get("$SERVER_URL/por/login_auth.csp?apiversion=1")
            val body = response.body?.string() ?: ""
            response.close()
            val alive = body.contains("<TwfID>")
            Log.d(TAG, "💓 Heartbeat: ${if (alive) "alive" else "expired"}")
            alive
        } catch (e: Exception) {
            Log.w(TAG, "💓 Heartbeat failed: ${e.message}")
            false
        }
    }

    /** 完整重连：EC + UAAP */
    suspend fun reconnect(): Boolean = withContext(Dispatchers.IO) {
        lastEcCaptchaRequired = false
        lastUaapPasswordChangeRequired = false
        try {
            Log.i(TAG, "🔄 Reconnecting...")
            close()
            startClient()
            val ec = ecLogin()
            lastEcCaptchaRequired = ec.failCaptchaRequired
            if (!ec.success) { Log.e(TAG, "🔄 EC re-login failed"); return@withContext false }
            val uaap = uaapLogin()
            lastUaapPasswordChangeRequired = uaap.failPasswordChangeRequired
            if (!uaap.success) { Log.e(TAG, "🔄 UAAP re-login failed"); return@withContext false }
            Log.i(TAG, "✅ Reconnect succeeded")
            true
        } catch (e: Exception) {
            Log.e(TAG, "🔄 Reconnect error", e)
            false
        }
    }

    /**
     * EC(VPN) 登录。
     * - [captchaCode] 为 null 或空：获取认证页；学校要求验证码时返回 failCaptchaRequired 并附图片，不提交密码。
     * - [captchaCode] 非空：必须使用上一次返回验证码时保存的认证上下文提交；上下文缺失或超过
     *   [CAPTCHA_TTL_MS] 时不提交，改为重新获取验证码（不计失败）。
     */
    suspend fun ecLogin(captchaCode: String? = null): ECLoginStatus = withContext(Dispatchers.IO) {
        try {
            performEcLogin(captchaCode?.takeIf { it.isNotEmpty() })
        } catch (e: EcStepFailure) {
            e.status
        } catch (e: Exception) {
            Log.e(TAG, "EC login error", e)
            ECLoginStatus(failUnknownError = true)
        }
    }

    private fun performEcLogin(captchaCode: String?): ECLoginStatus {
        if (captchaCode == null) {
            pendingCaptcha = null
            val page = fetchAuthPage()
            if (page.rndImg) return issueCaptchaChallenge(page)
            // 无需验证码：空验证码提交；若学校此时要求验证码（20041），换新认证页与图片
            val status = postEcLogin(page, captchaCode = "", codeSubmitted = false)
            return if (status.failCaptchaRequired) issueCaptchaChallenge(fetchAuthPage()) else status
        }

        // 上下文单次使用：取出即清空，无论提交结果如何都不复用
        val pending = pendingCaptcha
        pendingCaptcha = null
        if (pending == null || System.currentTimeMillis() - pending.createdAt > CAPTCHA_TTL_MS) {
            Log.i(TAG, "🔐 No valid captcha context, issuing a new challenge")
            return issueCaptchaChallenge(fetchAuthPage())
        }
        val status = postEcLogin(pending.page, captchaCode, codeSubmitted = true)
        return if (status.failCaptchaRequired) issueCaptchaChallenge(fetchAuthPage()) else status
    }

    /** GET 认证页并解析；失败抛出 [EcStepFailure] */
    private fun fetchAuthPage(): EcAuthPage {
        val response = client.get("$SERVER_URL/por/login_auth.csp?apiversion=1")
        val body = response.body?.string() ?: throw EcStepFailure(ECLoginStatus(failNetworkError = true))

        val twf = Regex("<TwfID>(.*?)</TwfID>").find(body)?.groupValues?.get(1)
            ?: throw EcStepFailure(ECLoginStatus(failNotFoundTwfid = true))
        val rsaKey = Regex("<RSA_ENCRYPT_KEY>(.*?)</RSA_ENCRYPT_KEY>").find(body)?.groupValues?.get(1)
            ?: throw EcStepFailure(ECLoginStatus(failNotFoundRsaKey = true))
        val rsaExp = Regex("<RSA_ENCRYPT_EXP>(.*?)</RSA_ENCRYPT_EXP>").find(body)?.groupValues?.get(1)
            ?: throw EcStepFailure(ECLoginStatus(failNotFoundRsaExp = true))
        val csrf = Regex("<CSRF_RAND_CODE>(.*?)</CSRF_RAND_CODE>").find(body)?.groupValues?.get(1)
            ?: throw EcStepFailure(ECLoginStatus(failNotFoundCsrfCode = true))
        val rndImg = Regex("<RndImg>(.*?)</RndImg>").find(body)?.groupValues?.get(1)?.trim() == "1"

        twfId = twf
        return EcAuthPage(twf, csrf, rsaKey, rsaExp, rndImg)
    }

    /** 为该认证页获取验证码图片，成功后保存单次使用的认证上下文 */
    private fun issueCaptchaChallenge(page: EcAuthPage): ECLoginStatus {
        val image = fetchCaptchaImage(page.twfId) ?: return ECLoginStatus(failUnknownError = true)
        pendingCaptcha = PendingCaptcha(page, System.currentTimeMillis())
        return ECLoginStatus(failCaptchaRequired = true, captchaImage = image)
    }

    /** GET /por/rand_code.csp；必须显式携带与认证页同一 TWFID 的 Cookie（与登录 POST 一致） */
    private fun fetchCaptchaImage(twfId: String): ByteArray? {
        val bytes = client.get(
            "$SERVER_URL/por/rand_code.csp",
            headers = mapOf("Cookie" to "TWFID=$twfId"),
        ).use { it.body?.bytes() }
        return bytes?.takeIf { it.isNotEmpty() }
    }

    /** 提交 login_psw.csp */
    private fun postEcLogin(page: EcAuthPage, captchaCode: String, codeSubmitted: Boolean): ECLoginStatus {
        val encryptedPassword = rsaEncrypt("${ecPassword}_${page.csrf}", page.rsaKey, page.rsaExp)
        val loginResponse = client.post(
            "$SERVER_URL/por/login_psw.csp?anti_replay=1&encrypt=1&type=cs",
            formData = mapOf(
                "svpn_rand_code" to captchaCode,
                "mitm" to "",
                "svpn_req_randcode" to page.csrf,
                "svpn_name" to userId,
                "svpn_password" to encryptedPassword,
            ),
            headers = mapOf("Cookie" to "TWFID=${page.twfId}"),
        )
        val loginBody = loginResponse.body?.string() ?: return ECLoginStatus(failNetworkError = true)

        return when {
            loginBody.contains("<Result>1</Result>") -> {
                twfId = page.twfId
                client.cookieJar.setCookie("TWFID", page.twfId, "vpn2.aufe.edu.cn")
                ecLogged = true
                simpleClient.copyCookiesFrom(client)
                noRedirectClient.copyCookiesFrom(client)
                ECLoginStatus(success = true)
            }
            else -> classifyEcLoginFailure(loginBody, codeSubmitted)
        }
    }

    /** login_psw 失败响应分类（协议顺序）：验证码 → 密码错误 → 未知 */
    private fun classifyEcLoginFailure(body: String, codeSubmitted: Boolean): ECLoginStatus {
        val captchaChallenge = body.contains("20023") ||
            body.contains("CAPTCHA required") ||
            body.contains("characters are incorrect")
        val maybeAttacked = body.contains("20041") ||
            body.contains("maybe attacked") ||
            body.contains("[CDATA[maybe attacked]]")
        return when {
            captchaChallenge && codeSubmitted -> ECLoginStatus(failCaptchaInvalid = true)
            captchaChallenge || maybeAttacked -> ECLoginStatus(failCaptchaRequired = true)
            body.contains("Invalid username or password!") || body.contains("20004") ->
                ECLoginStatus(failInvalidCredentials = true)
            else -> ECLoginStatus(failUnknownError = true)
        }
    }

    suspend fun uaapLogin(): UAAPLoginStatus = withContext(Dispatchers.IO) {
        try {
            performUaapLogin()
        } catch (e: Exception) {
            Log.e(TAG, "UAAP login error", e)
            UAAPLoginStatus(failUnknownError = true)
        }
    }

    private fun performUaapLogin(): UAAPLoginStatus {
        // 1. Get login page
        val response = client.get(UAAP_LOGIN_URL)
        val body = response.body?.string() ?: return UAAPLoginStatus(failNetworkError = true)

        // 2. Extract lt
        val ltMatch = Regex("""name="lt" value="(.*?)"""").find(body)
            ?: return UAAPLoginStatus(failNotFoundLt = true)
        val ltValue = ltMatch.groupValues[1]

        // 3. Extract execution
        val execMatch = Regex("""name="execution" value="(.*?)"""").find(body)
            ?: return UAAPLoginStatus(failNotFoundExecution = true)
        val executionValue = execMatch.groupValues[1]

        // 4. DES encrypt password
        val encryptedPassword = desEncrypt(password, ltValue)

        // 5. Submit login form
        val loginResponse = client.post(
            UAAP_LOGIN_URL,
            formData = mapOf(
                "username" to userId,
                "password" to encryptedPassword,
                "lt" to ltValue,
                "execution" to executionValue,
                "_eventId" to "submit",
                "submit" to "LOGIN",
            ),
        )
        val loginBody = loginResponse.body?.string() ?: return UAAPLoginStatus(failNetworkError = true)
        val responseUrl = loginResponse.request.url.toString()

        return when {
            // 学校强制改密：TGT 已铸出（密码正确）但 CAS 不签发票据，302 到改密页面。
            // 必须先于"密码错误"判定；该状态不可自动重试。
            responseUrl.contains("/mng/acp/completeInfo/password") ->
                UAAPLoginStatus(failPasswordChangeRequired = true)
            loginBody.contains("Invalid username or password") ||
                loginBody.contains("用户名或密码错误") ||
                loginBody.contains("密码输入错误") ||
                loginBody.contains("errorMsg") ->
                UAAPLoginStatus(failInvalidCredentials = true)
            responseUrl.startsWith("http://jwcxk2") || responseUrl.contains("ticket=") -> {
                uaapLogged = true
                simpleClient.copyCookiesFrom(client)
                noRedirectClient.copyCookiesFrom(client)
                UAAPLoginStatus(success = true)
            }
            else -> UAAPLoginStatus(failUnknownError = true)
        }
    }

    fun isHealthy(): Boolean = ecLogged && uaapLogged

    suspend fun close() = withContext(Dispatchers.IO) {
        runCatching { client.close() }
        runCatching { simpleClient.close() }
        runCatching { noRedirectClient.close() }
    }

    // ==================== Crypto ====================

    private fun rsaEncrypt(plaintext: String, modulusHex: String, exponentStr: String): String {
        val modulus = BigInteger(modulusHex, 16)
        val exponent = BigInteger(exponentStr)
        val publicKey = RSAKeyParameters(false, modulus, exponent)
        val encryptor = PKCS1Encoding(RSAEngine())
        encryptor.init(true, publicKey)
        val plainBytes = plaintext.toByteArray(Charsets.UTF_8)
        val encrypted = encryptor.processBlock(plainBytes, 0, plainBytes.size)
        return encrypted.joinToString("") { "%02x".format(it) }
    }

    private fun desEncrypt(plaintext: String, key: String): String {
        var keyBytes = key.toByteArray(Charsets.UTF_8)
        keyBytes = when {
            keyBytes.size > 8 -> keyBytes.copyOf(8)
            keyBytes.size < 8 -> keyBytes.copyOf(8)
            else -> keyBytes
        }
        // TripleDES: repeat 8-byte key 3 times
        val tripleKey = ByteArray(24)
        System.arraycopy(keyBytes, 0, tripleKey, 0, 8)
        System.arraycopy(keyBytes, 0, tripleKey, 8, 8)
        System.arraycopy(keyBytes, 0, tripleKey, 16, 8)

        val cipher = PaddedBufferedBlockCipher(DESedeEngine(), PKCS7Padding())
        cipher.init(true, KeyParameter(tripleKey))
        val input = plaintext.toByteArray(Charsets.UTF_8)
        val output = ByteArray(cipher.getOutputSize(input.size))
        val len = cipher.processBytes(input, 0, input.size, output, 0)
        val finalLen = cipher.doFinal(output, len)
        return Base64.encodeToString(output.copyOf(len + finalLen), Base64.NO_WRAP)
    }

    companion object {
        private const val TAG = "AUFEConnection"
        const val SERVER_URL = "https://vpn2.aufe.edu.cn"
        const val UAAP_LOGIN_URL =
            "http://uaap-aufe-edu-cn.vpn2.aufe.edu.cn:8118/cas/login?service=http%3A%2F%2Fjwcxk2.aufe.edu.cn%2Fj_spring_cas_security_check"
        const val TIMEOUT = 60_000L
        const val CAPTCHA_TTL_MS = 180_000L
    }
}
