package tech.loveace.appv3.data.service

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.*
import tech.loveace.appv3.data.model.*
import tech.loveace.appv3.data.network.AUFEConnection
import tech.loveace.appv3.data.network.PasswordChangeRequiredException

/**
 * 劳动俱乐部服务
 */
class LaborClubService(private val connection: AUFEConnection) {

    private var ticket: String? = null

    private suspend fun ensureTicket() {
        if (ticket != null) return
        withContext(Dispatchers.IO) { ticket = fetchTicket() }
    }

    private fun fetchTicket(): String? {
        try {
            var nextUrl = LOGIN_SERVICE_URL
            var redirectCount = 0
            while (redirectCount < 20) {
                val response = connection.noRedirectClient.get(nextUrl)
                val code = response.code
                val location = response.header("Location")
                if (code in 301..308 && location != null) {
                    nextUrl = location
                    // 学校强制改密拦截：CAS 校验通过但不签发票据，302 到改密页面。不是密码错误，不可重试
                    if (nextUrl.contains("/mng/acp/completeInfo/password")) {
                        Log.w(TAG, "fetchTicket: password change required")
                        throw PasswordChangeRequiredException()
                    }
                    if (nextUrl.contains("register?ticket=") || nextUrl.contains("#/register?ticket=")) {
                        val ticketMatch = Regex("ticket=([^&#]+)").find(nextUrl)
                        if (ticketMatch != null) return java.net.URLDecoder.decode(ticketMatch.groupValues[1], "UTF-8")
                    }
                    redirectCount++
                } else {
                    val body = response.body?.string() ?: ""
                    val bodyTicket = Regex("ticket=([^&\"#'\\s]+)").find(body)
                    if (bodyTicket != null) return java.net.URLDecoder.decode(bodyTicket.groupValues[1], "UTF-8")
                    break
                }
            }
        } catch (e: PasswordChangeRequiredException) { throw e } catch (e: Exception) { Log.e(TAG, "fetchTicket failed", e) }
        return null
    }

    private fun apiHeaders(): Map<String, String> {
        val headers = mutableMapOf<String, String>()
        ticket?.let { headers["ticket"] = it }
        connection.twfId?.let { headers["sdp-app-session"] = it }
        return headers
    }

    private val json = Json { ignoreUnknownKeys = true }

    /** 解析标准 API 响应 {code:0, data:...} */
    private fun parseRoot(body: String): JsonObject {
        val root = json.parseToJsonElement(body).jsonObject
        val code = root["code"]?.jsonPrimitive?.intOrNull
        if (code != 0) throw Exception("服务器返回错误代码: $code, msg: ${root["msg"]?.jsonPrimitive?.contentOrNull ?: ""}")
        return root
    }

    // ── 进度 ──
    suspend fun getProgress(): UniResponse<LaborClubProgressInfo> = withContext(Dispatchers.IO) {
        try {
            ensureTicket()
            if (ticket == null) throw Exception("无法获取劳动俱乐部 ticket")
            val resp = connection.simpleClient.post("$BASE_URL/User/Center/DoGetScoreInfo", formData = emptyMap(), headers = apiHeaders())
            val root = parseRoot(resp.body?.string() ?: throw Exception("响应为空"))
            val data = root["data"]?.jsonObject ?: throw Exception("缺少data")
            UniResponse.success(json.decodeFromJsonElement<LaborClubProgressInfo>(data))
        } catch (e: PasswordChangeRequiredException) { Log.w(TAG, "getProgress: password change required"); UniResponse.failure(PASSWORD_CHANGE_MESSAGE, retryable = false) } catch (e: Exception) { Log.e(TAG, "getProgress", e); UniResponse.failure(e.message ?: "获取进度失败", retryable = true) }
    }

    // ── 已加入活动 ──
    suspend fun getJoinedActivities(): UniResponse<List<LaborClubActivity>> = withContext(Dispatchers.IO) {
        try {
            ensureTicket()
            if (ticket == null) throw Exception("无法获取劳动俱乐部 ticket")
            val resp = connection.simpleClient.post("$BASE_URL/User/Activity/DoGetJoinPageList", formData = mapOf("pageIndex" to "1", "pageSize" to "100"), headers = apiHeaders())
            val root = parseRoot(resp.body?.string() ?: throw Exception("响应为空"))
            val dataElement = root["data"]
            val rows = when {
                dataElement is JsonArray -> dataElement
                dataElement is JsonObject -> dataElement["rows"]?.jsonArray ?: JsonArray(emptyList())
                else -> JsonArray(emptyList())
            }
            UniResponse.success(rows.map { json.decodeFromJsonElement<LaborClubActivity>(it) })
        } catch (e: PasswordChangeRequiredException) { Log.w(TAG, "getJoinedActivities: password change required"); UniResponse.failure(PASSWORD_CHANGE_MESSAGE, retryable = false) } catch (e: Exception) { Log.e(TAG, "getJoinedActivities", e); UniResponse.failure(e.message ?: "获取已参加活动失败", retryable = true) }
    }

    // ── 已加入俱乐部 ──
    suspend fun getJoinedClubs(): UniResponse<List<LaborClubInfo>> = withContext(Dispatchers.IO) {
        try {
            ensureTicket()
            if (ticket == null) throw Exception("无法获取劳动俱乐部 ticket")
            val resp = connection.simpleClient.post("$BASE_URL/User/Club/DoGetJoinList", formData = emptyMap(), headers = apiHeaders())
            val root = parseRoot(resp.body?.string() ?: throw Exception("响应为空"))
            val dataElement = root["data"]
            val rows = when {
                dataElement is JsonArray -> dataElement
                dataElement is JsonObject -> dataElement["rows"]?.jsonArray ?: JsonArray(emptyList())
                else -> JsonArray(emptyList())
            }
            UniResponse.success(rows.map { json.decodeFromJsonElement<LaborClubInfo>(it) })
        } catch (e: PasswordChangeRequiredException) { Log.w(TAG, "getJoinedClubs: password change required"); UniResponse.failure(PASSWORD_CHANGE_MESSAGE, retryable = false) } catch (e: Exception) { Log.e(TAG, "getJoinedClubs", e); UniResponse.failure(e.message ?: "获取俱乐部列表失败", retryable = true) }
    }

    // ── 俱乐部活动列表 ──
    suspend fun getClubActivities(clubId: String): UniResponse<List<LaborClubActivity>> = withContext(Dispatchers.IO) {
        try {
            ensureTicket()
            if (ticket == null) throw Exception("无法获取劳动俱乐部 ticket")
            val resp = connection.simpleClient.post("$BASE_URL/User/Activity/DoGetPageList",
                formData = mapOf("clubID" to clubId, "pageIndex" to "1", "pageSize" to "100"), headers = apiHeaders())
            val root = parseRoot(resp.body?.string() ?: throw Exception("响应为空"))
            val dataElement = root["data"]
            val rows = when {
                dataElement is JsonArray -> dataElement
                dataElement is JsonObject -> dataElement["rows"]?.jsonArray ?: JsonArray(emptyList())
                else -> JsonArray(emptyList())
            }
            UniResponse.success(rows.map { json.decodeFromJsonElement<LaborClubActivity>(it) })
        } catch (e: PasswordChangeRequiredException) { Log.w(TAG, "getClubActivities: password change required"); UniResponse.failure(PASSWORD_CHANGE_MESSAGE, retryable = false) } catch (e: Exception) { Log.e(TAG, "getClubActivities", e); UniResponse.failure(e.message ?: "获取俱乐部活动失败", retryable = true) }
    }

    // ── 报名活动 ──
    suspend fun applyActivity(activityId: String): UniResponse<String> = withContext(Dispatchers.IO) {
        try {
            ensureTicket()
            if (ticket == null) throw Exception("无法获取劳动俱乐部 ticket")
            val resp = connection.simpleClient.post("$BASE_URL/User/Activity/DoApplyJoin",
                formData = mapOf("activityID" to activityId, "reason" to ""), headers = apiHeaders())
            val body = resp.body?.string() ?: throw Exception("响应为空")
            val root = json.parseToJsonElement(body).jsonObject
            val code = root["code"]?.jsonPrimitive?.intOrNull
            val msg = root["msg"]?.jsonPrimitive?.contentOrNull ?: "报名成功"
            if (code != 0) UniResponse.failure<String>(msg, retryable = false)
            else UniResponse.success(msg, message = msg)
        } catch (e: PasswordChangeRequiredException) { Log.w(TAG, "applyActivity: password change required"); UniResponse.failure(PASSWORD_CHANGE_MESSAGE, retryable = false) } catch (e: Exception) { Log.e(TAG, "applyActivity", e); UniResponse.failure(e.message ?: "报名失败", retryable = false) }
    }

    // ── 签到列表 ──
    suspend fun getSignList(activityId: String): UniResponse<List<SignItem>> = withContext(Dispatchers.IO) {
        try {
            ensureTicket()
            if (ticket == null) throw Exception("无法获取劳动俱乐部 ticket")
            val resp = connection.simpleClient.post("$BASE_URL/User/Activity/DoGetSignList",
                formData = mapOf("activityID" to activityId, "type" to "1", "pageIndex" to "1", "pageSize" to "100"), headers = apiHeaders())
            val root = parseRoot(resp.body?.string() ?: throw Exception("响应为空"))
            val dataElement = root["data"]
            val rows = when {
                dataElement is JsonArray -> dataElement
                else -> JsonArray(emptyList())
            }
            UniResponse.success(rows.map { json.decodeFromJsonElement<SignItem>(it) })
        } catch (e: PasswordChangeRequiredException) { Log.w(TAG, "getSignList: password change required"); UniResponse.failure(PASSWORD_CHANGE_MESSAGE, retryable = false) } catch (e: Exception) { Log.e(TAG, "getSignList", e); UniResponse.failure(e.message ?: "获取签到列表失败", retryable = true) }
    }

    // ── 活动详情 ──
    suspend fun getActivityDetail(activityId: String): UniResponse<ActivityDetail> = withContext(Dispatchers.IO) {
        try {
            ensureTicket()
            if (ticket == null) throw Exception("无法获取劳动俱乐部 ticket")
            val resp = connection.simpleClient.post("$BASE_URL/User/Activity/DoGetDetail",
                formData = mapOf("id" to activityId), headers = apiHeaders())
            val root = parseRoot(resp.body?.string() ?: throw Exception("响应为空"))
            val data = root["data"]?.jsonObject ?: throw Exception("缺少data")

            // formData and teacherList are at root level, not inside data
            val formDataArr = root["formData"]?.jsonArray ?: JsonArray(emptyList())
            val teacherArr = root["teacherList"]?.jsonArray ?: JsonArray(emptyList())
            val signArr = data["SignList"]?.jsonArray ?: JsonArray(emptyList())

            val detail = ActivityDetail(
                id = data["ID"]?.jsonPrimitive?.contentOrNull ?: activityId,
                title = data["Title"]?.jsonPrimitive?.contentOrNull ?: "",
                startTime = data["StartTime"]?.jsonPrimitive?.contentOrNull ?: "",
                endTime = data["EndTime"]?.jsonPrimitive?.contentOrNull ?: "",
                chargeUserName = data["ChargeUserName"]?.jsonPrimitive?.contentOrNull ?: "",
                clubName = data["ClubName"]?.jsonPrimitive?.contentOrNull ?: "",
                memberNum = data["MemberNum"]?.jsonPrimitive?.intOrNull ?: 0,
                peopleNum = data["PeopleNum"]?.jsonPrimitive?.intOrNull ?: 0,
                signUpStartTime = data["SignUpStartTime"]?.jsonPrimitive?.contentOrNull ?: "",
                signUpEndTime = data["SignUpEndTime"]?.jsonPrimitive?.contentOrNull ?: "",
                formData = formDataArr.map { json.decodeFromJsonElement<ActivityFormField>(it) },
                teacherList = teacherArr.map { json.decodeFromJsonElement<ActivityTeacher>(it) },
                signList = signArr.map { json.decodeFromJsonElement<SignItem>(it) },
            )
            UniResponse.success(detail)
        } catch (e: PasswordChangeRequiredException) { Log.w(TAG, "getActivityDetail: password change required"); UniResponse.failure(PASSWORD_CHANGE_MESSAGE, retryable = false) } catch (e: Exception) { Log.e(TAG, "getActivityDetail", e); UniResponse.failure(e.message ?: "获取活动详情失败", retryable = true) }
    }

    // ── 扫码签到 ──
    suspend fun scanSignIn(qrData: String, location: String): UniResponse<SignInResponse> = withContext(Dispatchers.IO) {
        try {
            ensureTicket()
            if (ticket == null) throw Exception("无法获取劳动俱乐部 ticket")
            val resp = connection.simpleClient.post("$BASE_URL/User/Center/DoScanSignQRImage",
                formData = mapOf("content" to qrData, "location" to location), headers = apiHeaders())
            val result = json.decodeFromString<SignInResponse>(resp.body?.string() ?: throw Exception("响应为空"))
            UniResponse.success(result)
        } catch (e: PasswordChangeRequiredException) { Log.w(TAG, "scanSignIn: password change required"); UniResponse.failure(PASSWORD_CHANGE_MESSAGE, retryable = false) } catch (e: Exception) { Log.e(TAG, "scanSignIn", e); UniResponse.failure(e.message ?: "签到失败", retryable = false) }
    }

    companion object {
        private const val TAG = "LaborClubService"
        private const val PASSWORD_CHANGE_MESSAGE = "学校要求修改密码：请用浏览器登录学校教务系统完成密码修改，然后用新密码重新登录"
        const val BASE_URL = "http://api-ldjlb-ac-acxk-net.vpn2.aufe.edu.cn:8118"
        const val LOGIN_SERVICE_URL =
            "http://uaap-aufe-edu-cn.vpn2.aufe.edu.cn:8118/cas/login?service=http%3a%2f%2fapi.ldjlb.ac.acxk.net%2fUser%2fIndex%2fCoreLoginCallback%3fisCASGateway%3dtrue"
    }
}
