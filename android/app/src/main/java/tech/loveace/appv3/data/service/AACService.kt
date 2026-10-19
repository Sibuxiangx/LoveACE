package tech.loveace.appv3.data.service

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.*
import tech.loveace.appv3.data.model.*
import tech.loveace.appv3.data.network.AUFEConnection
import tech.loveace.appv3.data.network.PasswordChangeRequiredException

/**
 * 爱安财服务 - 第二课堂学分查询
 */
class AACService(private val connection: AUFEConnection) {

    private var ticket: String? = null

    private suspend fun ensureTicket() {
        if (ticket != null) return
        withContext(Dispatchers.IO) {
            ticket = fetchTicket()
        }
    }

    private fun fetchTicket(): String? {
        try {
            var nextUrl = LOGIN_SERVICE_URL
            var redirectCount = 0
            while (redirectCount < 20) {
                val response = connection.noRedirectClient.get(nextUrl)
                val code = response.code
                val location = response.header("Location")
                Log.d(TAG, "fetchTicket: code=$code, location=$location")
                if (code in 301..308 && location != null) {
                    nextUrl = location
                    // 学校强制改密拦截：CAS 校验通过但不签发票据，302 到改密页面。不是密码错误，不可重试
                    if (nextUrl.contains("/mng/acp/completeInfo/password")) {
                        Log.w(TAG, "fetchTicket: password change required")
                        throw PasswordChangeRequiredException()
                    }
                    // 检查是否到达 register 页面（包含应用 ticket）
                    if (nextUrl.contains("register?ticket=") || nextUrl.contains("#/register?ticket=")) {
                        val ticketMatch = Regex("ticket=([^&#]+)").find(nextUrl)
                        if (ticketMatch != null) {
                            Log.d(TAG, "fetchTicket: found app ticket in register redirect")
                            return java.net.URLDecoder.decode(ticketMatch.groupValues[1], "UTF-8")
                        }
                    }
                    redirectCount++
                } else {
                    // 非重定向响应 - 检查 body 中是否有 ticket
                    val body = response.body?.string() ?: ""
                    Log.d(TAG, "fetchTicket: final code=$code, body (first 500): ${body.take(500)}")
                    val bodyTicket = Regex("ticket=([^&\"#'\\s]+)").find(body)
                    if (bodyTicket != null) {
                        Log.d(TAG, "fetchTicket: found ticket in body")
                        return java.net.URLDecoder.decode(bodyTicket.groupValues[1], "UTF-8")
                    }
                    break
                }
            }
            Log.w(TAG, "fetchTicket: no ticket found after $redirectCount redirects")
        } catch (e: PasswordChangeRequiredException) {
            throw e
        } catch (e: Exception) {
            Log.e(TAG, "fetchTicket failed", e)
        }
        return null
    }

    private fun apiHeaders(): Map<String, String> {
        val headers = mutableMapOf<String, String>()
        ticket?.let { headers["ticket"] = it }
        connection.twfId?.let { headers["sdp-app-session"] = it }
        return headers
    }

    suspend fun getCreditInfo(): UniResponse<AACCreditInfo> = withContext(Dispatchers.IO) {
        try {
            ensureTicket()
            if (ticket == null) throw Exception("无法获取AAC ticket")
            val response = connection.simpleClient.post(
                "$BASE_URL/User/Center/DoGetScoreInfo?sf_request_type=ajax",
                formData = emptyMap(),
                headers = apiHeaders(),
            )
            val body = response.body?.string() ?: throw Exception("响应为空")
            if (response.code != 200) throw Exception("HTTP ${response.code}")
            val json = Json { ignoreUnknownKeys = true }
            val root = json.parseToJsonElement(body).jsonObject
            val code = root["code"]?.jsonPrimitive?.intOrNull
            if (code != 0) throw Exception("服务器返回错误代码: $code")
            val data = root["data"]?.jsonObject ?: throw Exception("响应缺少data字段")
            val info = AACCreditInfo(
                totalScore = data["TotalScore"]?.jsonPrimitive?.doubleOrNull ?: 0.0,
                isTypeAdopt = data["IsTypeAdopt"]?.jsonPrimitive?.booleanOrNull ?: false,
                typeAdoptResult = data["TypeAdoptResult"]?.jsonPrimitive?.contentOrNull ?: "",
            )
            UniResponse.success(info)
        } catch (e: PasswordChangeRequiredException) {
            Log.w(TAG, "getCreditInfo: password change required")
            UniResponse.failure(PASSWORD_CHANGE_MESSAGE, retryable = false)
        } catch (e: Exception) {
            Log.e(TAG, "getCreditInfo failed", e)
            UniResponse.failure(e.message ?: "获取爱安财信息失败", retryable = true)
        }
    }

    suspend fun getCreditList(): UniResponse<List<AACCreditCategory>> = withContext(Dispatchers.IO) {
        try {
            ensureTicket()
            if (ticket == null) throw Exception("无法获取AAC ticket")
            val response = connection.simpleClient.post(
                "$BASE_URL/User/Center/DoGetScoreList?sf_request_type=ajax",
                formData = mapOf("pageIndex" to "1", "pageSize" to "100"),
                headers = apiHeaders(),
            )
            val body = response.body?.string() ?: throw Exception("响应为空")
            if (response.code != 200) throw Exception("HTTP ${response.code}")
            val json = Json { ignoreUnknownKeys = true }
            val root = json.parseToJsonElement(body).jsonObject
            val code = root["code"]?.jsonPrimitive?.intOrNull
            if (code != 0) throw Exception("服务器返回错误代码: $code")
            val listData = root["data"]?.jsonArray ?: throw Exception("响应缺少data字段")
            val categories = listData.map { json.decodeFromJsonElement<AACCreditCategory>(it) }
            UniResponse.success(categories)
        } catch (e: PasswordChangeRequiredException) {
            Log.w(TAG, "getCreditList: password change required")
            UniResponse.failure(PASSWORD_CHANGE_MESSAGE, retryable = false)
        } catch (e: Exception) {
            Log.e(TAG, "getCreditList failed", e)
            UniResponse.failure(e.message ?: "获取爱安财明细失败", retryable = true)
        }
    }

    companion object {
        private const val TAG = "AACService"
        private const val PASSWORD_CHANGE_MESSAGE = "学校要求修改密码：请用浏览器登录学校教务系统完成密码修改，然后用新密码重新登录"
        const val BASE_URL = "http://api-dekt-ac-acxk-net.vpn2.aufe.edu.cn:8118"
        const val LOGIN_SERVICE_URL =
            "http://uaap-aufe-edu-cn.vpn2.aufe.edu.cn:8118/cas/login?service=http%3a%2f%2fapi.dekt.ac.acxk.net%2fUser%2fIndex%2fCoreLoginCallback%3fisCASGateway%3dtrue"
    }
}
