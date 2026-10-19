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
        lastUaapPasswordChangeRequired = false
        try {
            Log.i(TAG, "🔄 Reconnecting...")
            close()
            startClient()
            val ec = ecLogin()
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

    suspend fun ecLogin(): ECLoginStatus = withContext(Dispatchers.IO) {
        try {
            performEcLogin()
        } catch (e: Exception) {
            Log.e(TAG, "EC login error", e)
            ECLoginStatus(failUnknownError = true)
        }
    }

    private fun performEcLogin(): ECLoginStatus {
        // 1. Get auth params
        val response = client.get("$SERVER_URL/por/login_auth.csp?apiversion=1")
        val body = response.body?.string() ?: return ECLoginStatus(failNetworkError = true)

        // 2. Extract TwfID
        val twfMatch = Regex("<TwfID>(.*?)</TwfID>").find(body)
            ?: return ECLoginStatus(failNotFoundTwfid = true)
        twfId = twfMatch.groupValues[1]

        // 3. Extract RSA key
        val rsaKeyMatch = Regex("<RSA_ENCRYPT_KEY>(.*?)</RSA_ENCRYPT_KEY>").find(body)
            ?: return ECLoginStatus(failNotFoundRsaKey = true)
        val rsaKey = rsaKeyMatch.groupValues[1]

        // 4. Extract RSA exponent
        val rsaExpMatch = Regex("<RSA_ENCRYPT_EXP>(.*?)</RSA_ENCRYPT_EXP>").find(body)
            ?: return ECLoginStatus(failNotFoundRsaExp = true)
        val rsaExp = rsaExpMatch.groupValues[1]

        // 5. Extract CSRF code
        val csrfMatch = Regex("<CSRF_RAND_CODE>(.*?)</CSRF_RAND_CODE>").find(body)
            ?: return ECLoginStatus(failNotFoundCsrfCode = true)
        val csrfCode = csrfMatch.groupValues[1]

        // 6. RSA encrypt password
        val passwordToEncrypt = "${ecPassword}_$csrfCode"
        val encryptedPassword = rsaEncrypt(passwordToEncrypt, rsaKey, rsaExp)

        // 7. Login
        val loginResponse = client.post(
            "$SERVER_URL/por/login_psw.csp?anti_replay=1&encrypt=1&type=cs",
            formData = mapOf(
                "svpn_rand_code" to "",
                "mitm" to "",
                "svpn_req_randcode" to csrfCode,
                "svpn_name" to userId,
                "svpn_password" to encryptedPassword,
            ),
            headers = mapOf("Cookie" to "TWFID=$twfId"),
        )
        val loginBody = loginResponse.body?.string() ?: return ECLoginStatus(failNetworkError = true)

        return when {
            loginBody.contains("<Result>1</Result>") -> {
                client.cookieJar.setCookie("TWFID", twfId!!, "vpn2.aufe.edu.cn")
                ecLogged = true
                simpleClient.copyCookiesFrom(client)
                noRedirectClient.copyCookiesFrom(client)
                ECLoginStatus(success = true)
            }
            loginBody.contains("Invalid username or password!") ->
                ECLoginStatus(failInvalidCredentials = true)
            loginBody.contains("[CDATA[maybe attacked]]") || loginBody.contains("CAPTCHA required") ->
                ECLoginStatus(failMaybeAttacked = true)
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
                loginBody.contains("用户名或密码错误") ->
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
    }
}
