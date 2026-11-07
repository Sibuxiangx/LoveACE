package tech.loveace.appv3.data.service

import android.util.Log
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl
import okhttp3.Response
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import tech.loveace.appv3.data.model.AccessDirection
import tech.loveace.appv3.data.model.AccessKind
import tech.loveace.appv3.data.model.AccessPage
import tech.loveace.appv3.data.model.AccessRange
import tech.loveace.appv3.data.model.AccessRecord
import tech.loveace.appv3.data.model.BorrowRecord
import tech.loveace.appv3.data.model.BorrowingResult
import tech.loveace.appv3.data.model.ConsumptionPage
import tech.loveace.appv3.data.model.ConsumptionRecord
import tech.loveace.appv3.data.model.MailInitialPassword
import tech.loveace.appv3.data.model.UniResponse
import tech.loveace.appv3.data.network.AUFEConnection
import tech.loveace.appv3.data.network.HttpClient
import java.io.IOException

/**
 * 学校门户（all.aufe.edu.cn，经 VPN）cube 搜索服务：门禁记录、我的借阅、企业邮箱初始密码、一卡通消费记录。
 * 请求统一为 getList → counts → datas 三步；字段按列标题查找。
 */
class PortalService(private val connection: AUFEConnection) {

    @Volatile private var hrmResourceID: String? = null

    /** VPN 拦截冷却截止时间（毫秒时间戳），0 表示无冷却 */
    @Volatile private var interceptedUntil: Long = 0L

    /** 保护 [sessionInFlight]：并发的会话建立共享同一个结果 */
    private val sessionLock = Mutex()
    private var sessionInFlight: CompletableDeferred<String>? = null

    suspend fun accessRecords(kind: AccessKind, range: AccessRange, page: Int): UniResponse<AccessPage> =
        portalCall("accessRecords") { fetchAccessPage(kind, range, page) }

    suspend fun borrowing(): UniResponse<BorrowingResult> =
        portalCall("borrowing") { fetchBorrowing() }

    suspend fun consumptionRecords(page: Int): UniResponse<ConsumptionPage> =
        portalCall("consumptionRecords") { fetchConsumptionPage(page) }

    suspend fun mailInitialPassword(): UniResponse<MailInitialPassword?> =
        portalCall("mailInitialPassword") { fetchMailPassword() }

    // ==================== 业务读取 ====================

    private suspend fun fetchAccessPage(kind: AccessKind, range: AccessRange, page: Int): AccessPage {
        val customid = if (kind == AccessKind.DORMITORY) DORM_ACCESS_CUBE else LIBRARY_ACCESS_CUBE
        val dateField = if (kind == AccessKind.DORMITORY) DORM_ACCESS_DATE_FIELD else LIBRARY_ACCESS_DATE_FIELD
        val cube = fetchCubePage(customid, dateField, range.code(kind), page)
        val table = cube.table
        val offset = (page - 1) * ACCESS_PAGE_SIZE
        val records = table.rows.mapIndexed { index, row ->
            val id = table.recordID(row, offset + index)
            val time = table.value(row, "通过时间") ?: ""
            when (kind) {
                AccessKind.DORMITORY -> AccessRecord(
                    id = id,
                    time = time,
                    detail = table.value(row, "系统名称") ?: "",
                    direction = accessDirection(table.value(row, "通过方向")),
                )
                AccessKind.LIBRARY -> {
                    val campus = table.value(row, "校区") ?: ""
                    val date = table.value(row, "日期") ?: ""
                    AccessRecord(
                        id = id,
                        time = time,
                        detail = listOf(campus, date).filter { it.isNotEmpty() }.joinToString(" · "),
                        direction = null,
                    )
                }
            }
        }
        return AccessPage(records = records, total = cube.total)
    }

    private suspend fun fetchBorrowing(): BorrowingResult {
        val currentTable = fetchTable(BORROW_CURRENT_CUBE)
        val historyTable = fetchTable(BORROW_HISTORY_CUBE)
        val current = currentTable.rows.mapIndexed { index, row ->
            BorrowRecord(
                id = currentTable.recordID(row, index),
                title = currentTable.value(row, "书名") ?: "",
                borrowedAt = currentTable.value(row, "借阅时间") ?: "",
                returnedAt = null,
            )
        }
        val history = historyTable.rows.mapIndexed { index, row ->
            BorrowRecord(
                id = historyTable.recordID(row, index),
                title = historyTable.value(row, "书名") ?: "",
                borrowedAt = historyTable.value(row, "借书时间") ?: "",
                returnedAt = historyTable.value(row, "还书时间"),
            )
        }
        return BorrowingResult(current = current, history = history)
    }

    private suspend fun fetchConsumptionPage(page: Int): ConsumptionPage {
        val cube = fetchCubePage(CONSUMPTION_CUBE, CONSUMPTION_DATE_FIELD, CONSUMPTION_MONTH_CODE, page)
        val table = cube.table
        val offset = (page - 1) * CONSUMPTION_PAGE_SIZE
        val records = table.rows.mapIndexed { index, row ->
            ConsumptionRecord(
                id = table.recordID(row, offset + index),
                date = table.value(row, "交易日期") ?: "",
                time = table.value(row, "交易时间") ?: "",
                area = table.value(row, "交易地点") ?: "",
                amount = table.value(row, "交易金额") ?: "",
            )
        }
        return ConsumptionPage(records = records, total = cube.total)
    }

    private suspend fun fetchMailPassword(): MailInitialPassword? {
        val table = fetchTable(MAIL_PASSWORD_CUBE)
        val row = table.rows.firstOrNull() ?: return null
        val password = table.value(row, "邮箱初始密码")
        if (password.isNullOrEmpty()) {
            throw PortalFailure.ParseError("门户返回的数据缺少邮箱初始密码")
        }
        return MailInitialPassword(loginId = table.value(row, "登录名") ?: "", password = password)
    }

    // ==================== Cube 读取 ====================

    /** 读取整个 cube 的全部行（邮箱与借阅数据量小） */
    private suspend fun fetchTable(customid: Int): Table = resettingSession {
        val dataKey = openCube(customid, emptyMap())
        val total = countRows(dataKey)
        if (total <= 0) return@resettingSession Table(emptyList(), emptyList())

        var columns: List<JSONObject> = emptyList()
        val rows = mutableListOf<JSONObject>()
        var page = 1
        while (rows.size < total && page <= MAX_PAGES) {
            val json = loadDatas(dataKey, page)
            if (page == 1) columns = json.optJSONArray("columns").objects()
            val pageRows = json.optJSONArray("datas").objects()
            if (pageRows.isEmpty()) break
            rows += pageRows
            page++
        }
        Log.d(TAG, "portal cube $customid loaded ${rows.size} of $total rows")
        Table(columns, rows)
    }

    /** 单页读取（门禁、一卡通消费）：getList 带日期字段，counts 给总数，datas 只取当前页 */
    private suspend fun fetchCubePage(customid: Int, dateField: String, code: String, page: Int): CubePage =
        resettingSession {
            val dataKey = openCube(customid, mapOf("canIsQuickSearch" to "1", dateField to code))
            val total = countRows(dataKey)
            if (total <= 0) return@resettingSession CubePage(Table(emptyList(), emptyList()), 0)
            val json = loadDatas(dataKey, page)
            CubePage(
                table = Table(json.optJSONArray("columns").objects(), json.optJSONArray("datas").objects()),
                total = total,
            )
        }

    /** getList：返回 dataKey，必须是 32 位 */
    private suspend fun openCube(customid: Int, extra: Map<String, String>): String {
        val uid = ensureSession()
        val form = mapOf(
            "customid" to customid.toString(),
            "hrmResourceID" to uid,
            "guid" to "search",
            "isNewTableSearch" to "1",
            "displayType" to "",
            "isTempSearch" to "",
            "windowWidth" to WINDOW_WIDTH,
            "isTreeType" to "",
        ) + extra
        val json = parseObject(
            simpleClient().post(apiURL(LIST_PATH), formData = form, headers = apiHeaders()).toReply().body
        )
        val dataKey = jsonText(json.opt("datas"))
        if (dataKey == null || dataKey.length != 32) {
            throw PortalFailure.ParseError("门户列表响应缺少数据键")
        }
        return dataKey
    }

    private suspend fun countRows(dataKey: String): Int {
        val json = parseObject(
            simpleClient().post(apiURL(COUNTS_PATH), formData = mapOf("dataKey" to dataKey), headers = apiHeaders())
                .toReply().body
        )
        return jsonInt(json.opt("count")) ?: 0
    }

    private suspend fun loadDatas(dataKey: String, page: Int): JSONObject =
        parseObject(
            simpleClient().post(
                apiURL(DATAS_PATH),
                formData = mapOf("dataKey" to dataKey, "current" to page.toString(), "sortParams" to "[]"),
                headers = apiHeaders(),
            ).toReply().body
        )

    // ==================== 会话 ====================

    /** 会话失效时清掉缓存的 hrmResourceID，异常继续向上抛 */
    private suspend fun <T> resettingSession(block: suspend () -> T): T {
        try {
            return block()
        } catch (e: PortalFailure) {
            if (e is PortalFailure.SessionExpired) hrmResourceID = null
            throw e
        }
    }

    /** 门户会话只建立一次：并发调用共享同一次 SSO；失败不缓存 */
    private suspend fun ensureSession(): String {
        hrmResourceID?.let { return it }
        if (System.currentTimeMillis() < interceptedUntil) {
            throw PortalFailure.ParseError("学校 VPN 暂时拦截了门户请求，请彻底退出 App 后重新打开再试")
        }
        val (pending, owner) = sessionLock.withLock {
            val current = sessionInFlight
            if (current != null) {
                current to false
            } else {
                val created = CompletableDeferred<String>()
                sessionInFlight = created
                created to true
            }
        }
        if (!owner) return pending.await()
        return try {
            val uid = establishSession()
            pending.complete(uid)
            uid
        } catch (e: Throwable) {
            pending.completeExceptionally(
                if (e is CancellationException) IOException("门户会话建立已取消") else e
            )
            throw e
        } finally {
            withContext(NonCancellable) {
                sessionLock.withLock { sessionInFlight = null }
            }
        }
    }

    /** 逐跳走门户 CAS 入口（跳转地址映射到 VPN 域名），再用首页接口取得 hrmResourceID */
    private suspend fun establishSession(): String {
        val noRedirect = noRedirectClient()
        var next = SSO_ENTRY_URL
        for (hop in 0 until MAX_REDIRECTS) {
            val target = followSsoHop(noRedirect, next) ?: break
            next = target
        }

        val client = simpleClient()
        // 门户 CAS 跳转写入的会话 Cookie 在 noRedirect 的 jar 里；合并进请求用的 client，否则 hpdata 会被网关当成未登录
        client.mergeCookiesFrom(noRedirect)
        // 门户页加载时会先请求一次网页代理配置；结果不使用，失败不影响后续
        try {
            client.get("$BASE_URL/sf-webproxy/api/vpn-config", apiHeaders()).use { }
        } catch (_: IOException) {
        }

        val reply = client.post(
            apiURL(HPDATA_PATH),
            formData = HPDATA_FORM,
            headers = apiHeaders(),
        ).toReply()
        Log.d(TAG, "portal hpdata status=${reply.code} bytes=${reply.body.size}")
        if (reply.code == 404 && reply.errorHeader == "securityIntercept") {
            interceptedUntil = System.currentTimeMillis() + INTERCEPT_COOLDOWN_MILLIS
            Log.w(TAG, "portal hpdata intercepted by VPN; cooling down")
            throw PortalFailure.ParseError("学校 VPN 拦截了门户请求。请彻底退出 App 后重新打开再试")
        }
        val hpinfo = parseObject(reply.body).optJSONObject("hpinfo")
        val uid = jsonText(hpinfo?.opt("userid"))?.takeIf { it.isNotBlank() }
            ?: throw PortalFailure.SessionExpired
        hrmResourceID = uid
        interceptedUntil = 0L
        Log.d(TAG, "portal session established")
        return uid
    }

    /** 单跳：只有 301..308 且带 Location 才继续，返回映射到 VPN 域名后的下一跳地址 */
    private fun followSsoHop(client: HttpClient, url: String): String? =
        client.get(url).use { response ->
            val current = response.request.url
            Log.d(TAG, "portal sso hop status=${response.code} host=${current.host} path=${current.encodedPath}")
            if (response.code !in 301..308) return@use null
            val location = response.header("Location") ?: return@use null
            current.resolve(location)?.let { vpnURL(it) }
        }

    private fun vpnURL(url: HttpUrl): String {
        val host = url.host.lowercase()
        if (!host.endsWith("aufe.edu.cn") || host.endsWith("vpn2.aufe.edu.cn")) return url.toString()
        return url.newBuilder()
            .scheme("http")
            .host("${host.replace('.', '-')}.vpn2.aufe.edu.cn")
            .port(VPN_PORT)
            .build()
            .toString()
    }

    private fun apiURL(path: String): String = "$BASE_URL$path?sf_request_type=fetch"

    private fun apiHeaders(): Map<String, String> {
        val headers = mutableMapOf(
            "X-Requested-With" to "XMLHttpRequest",
            "Referer" to "$BASE_URL/spa/portal/static/index.html",
        )
        connection.twfId?.let { headers["sdp-app-session"] = it }
        return headers
    }

    private fun simpleClient(): HttpClient = try {
        connection.simpleClient
    } catch (_: UninitializedPropertyAccessException) {
        throw PortalFailure.NoSession
    }

    private fun noRedirectClient(): HttpClient = try {
        connection.noRedirectClient
    } catch (_: UninitializedPropertyAccessException) {
        throw PortalFailure.NoSession
    }

    // ==================== 错误与通用 ====================

    /** 统一把异常转成界面可直接显示的结果；只记录步骤名与异常类型，不记录内容 */
    private suspend fun <T> portalCall(step: String, block: suspend () -> T): UniResponse<T> =
        withContext(Dispatchers.IO) {
            try {
                UniResponse.success<T>(block())
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.w(TAG, "$step failed: ${e.javaClass.simpleName}")
                UniResponse.failure<T>(
                    error = portalMessage(e),
                    retryable = e !is PortalFailure.SessionExpired && e !is PortalFailure.NoSession,
                )
            }
        }

    private fun portalMessage(e: Exception): String = when (e) {
        is PortalFailure -> e.message ?: "加载失败，请稍后重试"
        is IOException -> "网络连接异常，请检查网络后重试"
        else -> "加载失败，请稍后重试"
    }

    private fun accessDirection(raw: String?): AccessDirection? = when (raw) {
        "0" -> AccessDirection.ENTRY
        "1" -> AccessDirection.EXIT
        else -> null
    }

    companion object {
        const val ACCESS_PAGE_SIZE = 10
        const val CONSUMPTION_PAGE_SIZE = 100

        private const val TAG = "PortalService"
        private const val BASE_URL = "http://all-aufe-edu-cn-s.vpn2.aufe.edu.cn:8118"
        private const val VPN_PORT = 8118
        private const val SSO_ENTRY_URL =
            "http://uaap-aufe-edu-cn.vpn2.aufe.edu.cn:8118/cas/login?service=http%3A%2F%2Fall.aufe.edu.cn%2Fwui%2Fcas-entrance.jsp%3Fpath%3Dhttps%253A%252F%252Fall.aufe.edu.cn%252Fwui%252Findex.html%2523%252Fmain%26ssoType%3DCAS"
        private const val MAX_REDIRECTS = 10
        private const val MAX_PAGES = 50
        private const val WINDOW_WIDTH = "390"
        private const val INTERCEPT_COOLDOWN_MILLIS = 180_000L

        private const val LIST_PATH = "/api/cube/search/getList"
        private const val COUNTS_PATH = "/api/ec/dev/table/counts"
        private const val DATAS_PATH = "/api/ec/dev/table/datas"
        private const val HPDATA_PATH = "/api/portal/homepage/hpdata"

        private const val MAIL_PASSWORD_CUBE = 82510
        private const val BORROW_CURRENT_CUBE = 84509
        private const val BORROW_HISTORY_CUBE = 84510
        private const val DORM_ACCESS_CUBE = 37501
        private const val DORM_ACCESS_DATE_FIELD = "178950"
        private const val LIBRARY_ACCESS_CUBE = 71001
        private const val LIBRARY_ACCESS_DATE_FIELD = "316587"
        private const val CONSUMPTION_CUBE = 74507
        private const val CONSUMPTION_DATE_FIELD = "299018"
        /** 一卡通消费固定查询"本月" */
        private const val CONSUMPTION_MONTH_CODE = "3"

        private val HPDATA_FORM = mapOf(
            "hpid" to "38522",
            "subCompanyId" to "21",
            "menuIds" to "-665,-1001",
            "menuPathIds" to "-665,-1001",
            "isSetting" to "false",
            "isfromportal" to "1",
            "isfromhp" to "0",
        )
    }
}

/** 门户内部失败；message 即界面文案 */
private sealed class PortalFailure(message: String) : Exception(message) {
    object SessionExpired : PortalFailure("门户会话已失效，请重新登录")
    object NoSession : PortalFailure("请先登录")
    object EmptyResponse : PortalFailure("门户没有返回数据")
    class ParseError(message: String) : PortalFailure(message)
}

private class Table(private val columns: List<JSONObject>, val rows: List<JSONObject>) {
    /** 列标题对应的 dbField */
    fun field(title: String): String? =
        columns.firstOrNull { it.optString("title") == title }?.let { jsonText(it.opt("dbField")) }

    fun text(row: JSONObject, field: String?): String? = field?.let { jsonText(row.opt(it)) }

    fun value(row: JSONObject, title: String): String? = text(row, field(title))

    fun recordID(row: JSONObject, index: Int): String = value(row, "数据ID") ?: "row-$index"
}

private class CubePage(val table: Table, val total: Int)

private class Reply(val code: Int, val errorHeader: String?, val body: ByteArray)

private fun Response.toReply(): Reply = use { r ->
    Reply(r.code, r.header("Errormsg"), r.body?.bytes() ?: ByteArray(0))
}

private fun JSONArray?.objects(): List<JSONObject> {
    if (this == null) return emptyList()
    return (0 until length()).mapNotNull { optJSONObject(it) }
}

private fun jsonText(value: Any?): String? = when (value) {
    null, JSONObject.NULL -> null
    is String -> value
    is Number -> value.toString()
    else -> null
}

private fun jsonInt(value: Any?): Int? = when (value) {
    is Number -> value.toInt()
    is String -> value.toIntOrNull()
    else -> null
}

/**
 * 解析 JSON 对象。空响应视为"没有返回数据"；非 JSON 且内容像 VPN 登录页的视为会话失效。
 */
private fun parseObject(bytes: ByteArray): JSONObject {
    if (bytes.isEmpty()) throw PortalFailure.EmptyResponse
    val text = String(bytes, Charsets.UTF_8)
    try {
        return JSONObject(text)
    } catch (_: JSONException) {
    }
    val head = String(bytes, 0, minOf(512, bytes.size), Charsets.UTF_8).lowercase()
    if (head.contains("<html") || head.contains("login_auth.csp") || head.contains("svpn_name")) {
        throw PortalFailure.SessionExpired
    }
    throw PortalFailure.ParseError("门户响应格式异常")
}
