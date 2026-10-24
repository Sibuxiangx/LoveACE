package tech.loveace.appv3.data.service

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.*
import org.jsoup.Jsoup
import tech.loveace.appv3.data.model.*
import tech.loveace.appv3.data.network.AUFEConnection
import java.net.URLEncoder

/** 教学楼（TeachBuildingName 接口）。stopped = 备注或名称含"停用"。 */
data class FcBuilding(
    val campusNo: String,
    val campusName: String,
    val no: String,
    val name: String,
    val stopped: Boolean,
)

/** 停用原因：名称含"停用"（始终显示）；状态码 02 / 03（默认隐藏，随"显示停用教室"开关显示）。 */
enum class FcStopReason { NAME, STATUS_02, STATUS_03 }

/** 合并后的教室（按楼宇 + 房号去重）。 */
data class FcRoom(
    val campusNo: String,
    val campusName: String,
    val buildingNo: String,
    val buildingName: String,
    /** 详情页使用的编号（classroomNumber） */
    val number: String,
    /** 展示名：去掉"（停用）"等后缀 */
    val title: String,
    /** 房号，如 302、1001；取不到时为原始编号 */
    val code: String,
    /** 推测楼层：三位数取首位，四位数取前两位；取不到或超过 12 为 null（归入"其他"） */
    val floor: Int?,
    val seats: Int?,
    val typeCode: String?,
    val typeName: String?,
    val stopReasons: Set<FcStopReason>,
) {
    val stopped: Boolean get() = stopReasons.isNotEmpty()
    /** 状态码 02 或 03：默认隐藏，打开"显示停用教室"后显示。 */
    val statusHidden: Boolean get() = FcStopReason.STATUS_02 in stopReasons || FcStopReason.STATUS_03 in stopReasons
}

/** 合并前的原始行（classroomJson 或 search 结果的一条）。 */
data class FcRawRoom(
    val campusNo: String,
    val campusName: String,
    val buildingNo: String,
    val buildingName: String,
    val number: String,
    val name: String,
    val statusCode: String,
    val typeCode: String?,
    val typeName: String?,
    val seats: Int?,
)

data class FcOption(val code: String, val name: String)

/** 元信息：当前教学周（页面头部"第 N 周"）与教室类型选项。 */
data class FcMeta(val currentWeek: Int?, val types: List<FcOption>)

/** 时段：weekday 1..7（周一..周日），section 1..10。 */
data class FcSlot(val weekday: Int, val section: Int)

/** 空闲查询条件。weeks 只取一周时即为单周；slots 为交集条件。空字符串表示不限。 */
data class FcQuery(
    val weeks: List<Int>,
    val slots: List<FcSlot>,
    val campusNo: String = "",
    val buildingNo: String = "",
    val typeCode: String = "",
)

/** 纯规则：不做网络请求。 */
object FreeClassroomRules {
    private val PAREN_STOP = Regex("[（(][^）)]*停用[^）)]*[）)]")
    private val TRAILING_DASH_DIGIT = Regex("-\\d$")
    private val NAME_CODE = Regex("(\\d{3,4})\\s*$")
    private val NUMBER_DASH_CODE = Regex("-(\\d{3,4})(-[A-Za-z])?$")
    private val NUMBER_CODE = Regex("(\\d{3,4})$")

    /** 虚拟考场（如"在线考试虚拟考场"，座位数 50000）不是实体教室。 */
    fun isVirtual(name: String, seats: Int?): Boolean =
        name.contains("虚拟") || (seats ?: 0) > 1000

    /** 去掉"（停用）""（录播）"之外的停用括号，保留其它文字。 */
    fun cleanName(name: String): String = name.replace(PAREN_STOP, "").trim()

    /**
     * 房号：先从名称末尾取 3–4 位数字（去掉停用后缀和 -1/-2 之类的重复标记），
     * 取不到再从编号取；都取不到就用原始编号。
     */
    fun codeOf(number: String, name: String): String {
        val base = cleanName(name).replace(TRAILING_DASH_DIGIT, "")
        NAME_CODE.find(base)?.let { return it.groupValues[1] }
        NUMBER_DASH_CODE.find(number)?.let { return it.groupValues[1] }
        NUMBER_CODE.find(number)?.let { return it.groupValues[1] }
        return number
    }

    /** 推测楼层。三位数取首位，四位数取前两位（通慧楼 1001–1005 为 10 层）。 */
    fun floorOf(code: String): Int? {
        if (code.isEmpty() || !code.all { it.isDigit() }) return null
        val floor = when (code.length) {
            3 -> code.substring(0, 1).toInt()
            4 -> code.substring(0, 2).toInt()
            else -> return null
        }
        return if (floor in 1..12) floor else null
    }

    fun stopReasons(name: String, statusCode: String): Set<FcStopReason> = buildSet {
        if (name.contains("停用")) add(FcStopReason.NAME)
        when (statusCode) {
            "02" -> add(FcStopReason.STATUS_02)
            "03" -> add(FcStopReason.STATUS_03)
        }
    }

    /**
     * 同一楼宇、同一房号的多行合并为一间。
     * 任一行是停用（名称含停用、或状态 02 / 03）即视为停用，并保留原因。
     */
    fun merge(rows: List<FcRawRoom>): List<FcRoom> {
        val groups = LinkedHashMap<String, MutableList<FcRawRoom>>()
        rows.filterNot { isVirtual(it.name, it.seats) }.forEach { row ->
            val code = codeOf(row.number, row.name)
            groups.getOrPut("${row.campusNo}|${row.buildingNo}|$code") { mutableListOf() }.add(row)
        }
        return groups.map { (key, list) ->
            val first = list.first()
            val code = key.substringAfterLast('|')
            val preferred = list.firstOrNull { !it.name.contains("停用") } ?: first
            FcRoom(
                campusNo = first.campusNo,
                campusName = first.campusName,
                buildingNo = first.buildingNo,
                buildingName = first.buildingName,
                number = preferred.number,
                title = cleanName(preferred.name).ifEmpty { preferred.number },
                code = code,
                floor = floorOf(code),
                seats = list.firstNotNullOfOrNull { it.seats },
                typeCode = list.firstNotNullOfOrNull { it.typeCode },
                typeName = list.firstNotNullOfOrNull { it.typeName },
                stopReasons = list.flatMap { stopReasons(it.name, it.statusCode) }.toSet(),
            )
        }
    }
}

/**
 * 空闲教室查询服务（教务系统"空闲教室查询 · 自定义"页面与"教室课表"页面的接口）。
 * 占用信息来自教室详情页的隐藏域 wsSection，格式 weekday_week_section，逗号分隔。
 */
class FreeClassroomService(private val connection: AUFEConnection) {

    /** 两个校区的全部教学楼。 */
    suspend fun loadBuildings(): UniResponse<List<FcBuilding>> = withContext(Dispatchers.IO) {
        try {
            val url = "$BASE_URL/student/teachingResources/freeClassroomQuery/TeachBuildingName"
            val result = mutableListOf<FcBuilding>()
            for (campusNo in listOf("2", "1")) {
                val body = connection.client.post(
                    url,
                    formData = mapOf("codeCamListName" to campusNo),
                    headers = AJAX_HEADERS,
                ).body?.string() ?: throw Exception("教学楼列表为空")
                Json.parseToJsonElement(body).jsonArray.forEach { element ->
                    val obj = element.jsonObject
                    val no = obj["id"]?.jsonObject?.get("teachingBuildingNumber")?.jsonPrimitive?.contentOrNull
                        ?: return@forEach
                    val name = obj["teachingBuildingName"]?.jsonPrimitive?.contentOrNull.orEmpty()
                    val remark = obj["remark"]?.jsonPrimitive?.contentOrNull.orEmpty()
                    result.add(
                        FcBuilding(
                            campusNo = campusNo,
                            campusName = campusNameOf(campusNo),
                            no = no,
                            name = name,
                            stopped = remark.contains("停用") || name.contains("停用"),
                        ),
                    )
                }
            }
            UniResponse.success(result)
        } catch (e: Exception) {
            Log.e(TAG, "loadBuildings failed", e)
            UniResponse.failure(e.message ?: "获取教学楼失败", retryable = true)
        }
    }

    /** 当前教学周与教室类型选项，都在查询页的静态 HTML 中。 */
    suspend fun loadMeta(): UniResponse<FcMeta> = withContext(Dispatchers.IO) {
        try {
            val url = "$BASE_URL/student/teachingResources/freeClassroomQuery/custom"
            val html = connection.client.get(url).body?.string() ?: throw Exception("页面为空")
            val week = Regex("第\\s*(\\d+)\\s*周").find(html)?.groupValues?.get(1)?.toIntOrNull()
            val types = Jsoup.parse(html).select("select#jslxdm option").mapNotNull { option ->
                val code = option.attr("value").takeIf { it.isNotEmpty() } ?: return@mapNotNull null
                FcOption(code, option.text().trim())
            }
            UniResponse.success(FcMeta(week, types))
        } catch (e: Exception) {
            Log.e(TAG, "loadMeta failed", e)
            UniResponse.failure(e.message ?: "获取教学周失败", retryable = true)
        }
    }

    /** 今天的当前节次（来自"今天"页面的 sec）。取不到返回 null。 */
    suspend fun currentSection(): Int? = withContext(Dispatchers.IO) {
        try {
            val url = "$BASE_URL/student/teachingResources/freeClassroom/today"
            val html = connection.client.get(url).body?.string() ?: return@withContext null
            Regex("var sec = parseInt\\('(\\d+)'\\)").find(html)?.groupValues?.get(1)?.toIntOrNull()
        } catch (e: Exception) {
            Log.w(TAG, "currentSection failed", e)
            null
        }
    }

    /** 某楼的全部教室（教室课表接口，不受周次和节次影响）。 */
    suspend fun listRooms(building: FcBuilding, typeNames: Map<String, String>): UniResponse<List<FcRoom>> =
        withContext(Dispatchers.IO) {
            try {
                val url = "$BASE_URL/student/teachingResources/classroomCurriculum/${building.campusNo}/${building.no}/classroomJson"
                val body = connection.client.get(url).body?.string() ?: throw Exception("教室列表为空")
                val rows = Json.parseToJsonElement(body).jsonArray.mapNotNull { element ->
                    parseRoomJson(element.jsonObject, building, typeNames)
                }
                UniResponse.success(FreeClassroomRules.merge(rows))
            } catch (e: Exception) {
                Log.e(TAG, "listRooms failed", e)
                UniResponse.failure(e.message ?: "获取教室列表失败", retryable = true)
            }
        }

    /** 空闲查询：只返回所选周次与节次全部空闲的教室。分页读取直到取完。 */
    suspend fun search(query: FcQuery, typeNames: Map<String, String> = emptyMap()): UniResponse<List<FcRoom>> =
        withContext(Dispatchers.IO) {
            try {
                val url = "$BASE_URL/student/teachingResources/freeClassroomQuery/search"
                val weeks = query.weeks.sorted().joinToString(",")
                val wSection = query.slots
                    .sortedWith(compareBy<FcSlot>({ it.weekday }, { it.section }))
                    .joinToString(",") { "${it.weekday}/${it.section}" }
                val raw = mutableListOf<FcRawRoom>()
                var page = 1
                while (page <= MAX_PAGES) {
                    val body = connection.client.post(
                        url,
                        formData = mapOf(
                            "weeks" to weeks,
                            "jslxdm" to query.typeCode,
                            "codeCampusListNumber" to query.campusNo,
                            "teaNum" to query.buildingNo,
                            "wSection" to wSection,
                            "pageNum" to page.toString(),
                            "pageSize" to SEARCH_PAGE_SIZE.toString(),
                        ),
                        headers = AJAX_HEADERS,
                    ).body?.string() ?: throw Exception("查询结果为空")
                    val first = Json.parseToJsonElement(body).jsonArray.firstOrNull()?.jsonObject
                        ?: throw Exception("查询结果格式异常")
                    val total = first["pageContext"]?.jsonObject?.get("totalCount")?.jsonPrimitive?.intOrNull ?: 0
                    val records = (first["records"] as? JsonArray)?.toList() ?: emptyList()
                    records.forEach { element ->
                        parseSearchRecord(element.jsonObject, typeNames)?.let { raw.add(it) }
                    }
                    if (records.isEmpty() || raw.size >= total) break
                    page++
                }
                UniResponse.success(FreeClassroomRules.merge(raw))
            } catch (e: Exception) {
                Log.e(TAG, "search failed", e)
                UniResponse.failure(e.message ?: "查询空闲教室失败", retryable = true)
            }
        }

    /** 单间教室的占用：返回 "weekday_week_section" 集合，空集合 = 整周空闲。 */
    suspend fun occupancy(room: FcRoom): UniResponse<Set<String>> = withContext(Dispatchers.IO) {
        try {
            val query = listOf(
                "campusName" to room.campusName,
                "teachingBuildingName" to room.buildingName,
                "classroomName" to room.number,
                "campusNumber" to room.campusNo,
                "teachingBuildingNumber" to room.buildingNo,
                "classroomNumber" to room.number,
            ).joinToString("&") { (key, value) -> "$key=${URLEncoder.encode(value, "UTF-8")}" }
            val url = "$BASE_URL/student/teachingResources/freeClassroomQuery/classroomQuery?$query"
            val html = connection.client.get(url).body?.string() ?: throw Exception("教室详情为空")
            val value = Jsoup.parse(html).getElementById("wsSection")?.attr("value")
                ?: throw Exception("占用信息缺失")
            UniResponse.success(value.split(",").map { it.trim() }.filter { it.isNotEmpty() }.toSet())
        } catch (e: Exception) {
            Log.e(TAG, "occupancy failed", e)
            UniResponse.failure(e.message ?: "获取占用信息失败", retryable = true)
        }
    }

    private fun parseRoomJson(
        obj: JsonObject,
        building: FcBuilding,
        typeNames: Map<String, String>,
    ): FcRawRoom? {
        val number = obj["id"]?.jsonObject?.get("classroomNumber")?.jsonPrimitive?.contentOrNull ?: return null
        val typeCode = obj["classroomTypeCode"]?.jsonPrimitive?.contentOrNull
        return FcRawRoom(
            campusNo = building.campusNo,
            campusName = building.campusName,
            buildingNo = building.no,
            buildingName = building.name,
            number = number,
            name = obj["classroomName"]?.jsonPrimitive?.contentOrNull ?: number,
            statusCode = obj["classroomStatusCode"]?.jsonPrimitive?.contentOrNull.orEmpty(),
            typeCode = typeCode,
            typeName = typeCode?.let { typeNames[it] },
            seats = obj["placeNum"]?.jsonPrimitive?.contentOrNull?.toIntOrNull(),
        )
    }

    private fun parseSearchRecord(obj: JsonObject, typeNames: Map<String, String>): FcRawRoom? {
        val id = obj["id"]?.jsonObject ?: return null
        val number = id["classroomNumber"]?.jsonPrimitive?.contentOrNull ?: return null
        val typeCode = obj["classroomTypeCode"]?.jsonPrimitive?.contentOrNull
        return FcRawRoom(
            campusNo = id["campusNumber"]?.jsonPrimitive?.contentOrNull.orEmpty(),
            campusName = obj["campusName"]?.jsonPrimitive?.contentOrNull.orEmpty(),
            buildingNo = id["teachingBuildingNumber"]?.jsonPrimitive?.contentOrNull.orEmpty(),
            buildingName = obj["teachingBuildingName"]?.jsonPrimitive?.contentOrNull.orEmpty(),
            number = number,
            name = obj["classroomName"]?.jsonPrimitive?.contentOrNull ?: number,
            statusCode = obj["classroomStatusCode"]?.jsonPrimitive?.contentOrNull.orEmpty(),
            typeCode = typeCode,
            typeName = obj["classroomTypeName"]?.jsonPrimitive?.contentOrNull ?: typeCode?.let { typeNames[it] },
            seats = obj["classNumberOfSeats"]?.jsonPrimitive?.contentOrNull?.toIntOrNull(),
        )
    }

    private fun campusNameOf(campusNo: String): String = when (campusNo) {
        "2" -> "西校"
        "1" -> "东校"
        else -> campusNo
    }

    companion object {
        private const val TAG = "FreeClassroomService"
        const val BASE_URL = "http://jwcxk2-aufe-edu-cn.vpn2.aufe.edu.cn:8118"
        private const val SEARCH_PAGE_SIZE = 200
        private const val MAX_PAGES = 10
        private val AJAX_HEADERS = mapOf(
            "X-Requested-With" to "XMLHttpRequest",
            "Accept" to "application/json, text/javascript, */*; q=0.01",
        )
    }
}
