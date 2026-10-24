package tech.loveace.appv3.data.service

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.*
import org.jsoup.Jsoup
import org.jsoup.nodes.Document
import org.jsoup.nodes.Element
import tech.loveace.appv3.data.model.*
import tech.loveace.appv3.data.network.AUFEConnection

/**
 * 课程开课查询服务
 * - loadIndex：学期列表与下拉选项（同一个 index 页解析）
 * - queryPage：分片查询开课记录，调用方逐页拉取，不做整学期全量拉取
 */
class CourseScheduleService(private val connection: AUFEConnection) {

    data class ScheduleTermItem(
        val termCode: String,
        val termName: String,
        val isSelected: Boolean = false,
    )

    data class CourseScheduleOption(val code: String, val name: String)

    /** 下拉选项。页面中缺少对应 select 时该列表为空，UI 据此隐藏该筛选项 */
    data class CourseScheduleOptions(
        val departments: List<CourseScheduleOption> = emptyList(), // kkxsh 开课院系
        val campuses: List<CourseScheduleOption> = emptyList(),    // kkxqh 开课校区
        val buildings: List<CourseScheduleOption> = emptyList(),   // jxlh 教学楼
        val categories: List<CourseScheduleOption> = emptyList(),  // kclb 课程类别
    )

    data class CourseScheduleIndex(
        val terms: List<ScheduleTermItem>,
        val options: CourseScheduleOptions,
    )

    /** 查询条件。空字符串或 null 表示不限 */
    data class CourseScheduleQuery(
        val termCode: String,
        val kch: String = "",   // 课程号
        val kcm: String = "",   // 课程名
        val skjs: String = "",  // 授课教师
        val kkxsh: String = "", // 开课院系代码
        val kkxqh: String = "", // 开课校区代码
        val jxlh: String = "",  // 教学楼代码
        val kclb: String = "",  // 课程类别代码
        val skxq: Int? = null,  // 上课星期 1..7
        val skjc: Int? = null,  // 开始节次 1..10
    )

    data class CourseSchedulePage(
        val records: List<CourseScheduleRecord>,
        val totalCount: Int,
    )

    suspend fun loadIndex(): UniResponse<CourseScheduleIndex> = withContext(Dispatchers.IO) {
        try {
            val url = "$BASE_URL/student/integratedQuery/course/courseSchdule/index"
            val response = connection.client.get(url)
            val html = response.body?.string() ?: throw Exception("响应为空")
            val doc = Jsoup.parse(html)
            val select = selectOf(doc, "zxjxjhh") ?: throw Exception("未找到学期选择框")
            val terms = select.select("option").mapNotNull { option ->
                val code = option.attr("value").takeIf { it.isNotEmpty() } ?: return@mapNotNull null
                ScheduleTermItem(code, option.text().trim(), option.hasAttr("selected"))
            }
            if (terms.isEmpty()) throw Exception("未能解析出任何学期信息")
            val options = CourseScheduleOptions(
                departments = parseOptions(doc, "kkxsh"),
                campuses = parseOptions(doc, "kkxqh"),
                buildings = parseOptions(doc, "jxlh"),
                categories = parseOptions(doc, "kclb"),
            )
            UniResponse.success(CourseScheduleIndex(terms, options))
        } catch (e: Exception) {
            Log.e(TAG, "loadIndex failed", e)
            UniResponse.failure(e.message ?: "获取学期列表失败", retryable = true)
        }
    }

    suspend fun queryPage(
        query: CourseScheduleQuery,
        pageNum: Int,
        pageSize: Int = PAGE_SIZE,
    ): UniResponse<CourseSchedulePage> = withContext(Dispatchers.IO) {
        try {
            UniResponse.success(fetchPage(query, pageNum, pageSize))
        } catch (e: Exception) {
            Log.e(TAG, "queryPage failed", e)
            UniResponse.failure(e.message ?: "查询开课失败", retryable = true)
        }
    }

    private fun fetchPage(query: CourseScheduleQuery, pageNum: Int, pageSize: Int): CourseSchedulePage {
        val url = "$BASE_URL/student/integratedQuery/course/courseSchdule/courseInfo?sf_request_type=ajax"
        val response = connection.client.post(url, formData = mapOf(
            "zxjxjhh" to query.termCode, "kch" to query.kch, "kcm" to query.kcm,
            "kkxsh" to query.kkxsh, "kkxqh" to query.kkxqh, "jxlh" to query.jxlh, "jash" to "",
            "skxq" to (query.skxq?.toString() ?: ""), "skjc" to (query.skjc?.toString() ?: ""),
            "kclb" to query.kclb, "skjs" to query.skjs,
            "xqname" to "", "jcname" to "", "jxlname" to "", "jasname" to "",
            "pageNum" to pageNum.toString(), "pageSize" to pageSize.toString(),
        ))
        val body = response.body?.string() ?: throw Exception("响应为空")
        val data = Json { ignoreUnknownKeys = true }.parseToJsonElement(body).jsonObject
        val listObj = data["list"]?.jsonObject ?: throw Exception("查询结果格式异常")
        val pageContext = listObj["pageContext"]?.jsonObject
        val totalCount = pageContext?.get("totalCount")?.jsonPrimitive?.intOrNull
            ?: listObj["totalCount"]?.jsonPrimitive?.intOrNull
            ?: 0
        val records = listObj["records"]?.jsonArray ?: return CourseSchedulePage(emptyList(), totalCount)
        return CourseSchedulePage(records.mapNotNull { parseCourseScheduleRecord(it.jsonObject) }, totalCount)
    }

    private fun selectOf(doc: Document, name: String): Element? =
        doc.selectFirst("select#$name") ?: doc.selectFirst("select[name=$name]")

    private fun parseOptions(doc: Document, name: String): List<CourseScheduleOption> {
        val select = selectOf(doc, name) ?: return emptyList()
        return select.select("option").mapNotNull { option ->
            val code = option.attr("value").takeIf { it.isNotEmpty() } ?: return@mapNotNull null
            CourseScheduleOption(code, option.text().trim())
        }
    }

    private fun parseCourseScheduleRecord(obj: JsonObject): CourseScheduleRecord {
        return CourseScheduleRecord(
            kch = obj["kch"]?.jsonPrimitive?.contentOrNull,
            kxh = obj["kxh"]?.jsonPrimitive?.contentOrNull,
            kcm = obj["kcm"]?.jsonPrimitive?.contentOrNull,
            xf = obj["xf"]?.jsonPrimitive?.intOrNull,
            xs = obj["xs"]?.jsonPrimitive?.intOrNull,
            kkxsjc = obj["kkxsjc"]?.jsonPrimitive?.contentOrNull,
            kslxmc = obj["kslxmc"]?.jsonPrimitive?.contentOrNull,
            skjs = obj["skjs"]?.jsonPrimitive?.contentOrNull,
            bkskrl = obj["bkskrl"]?.jsonPrimitive?.intOrNull,
            bkskyl = obj["bkskyl"]?.jsonPrimitive?.intOrNull,
            xkmssm = obj["xkmssm"]?.jsonPrimitive?.contentOrNull,
            kkxqm = obj["kkxqm"]?.jsonPrimitive?.contentOrNull,
            skzc = obj["skzc"]?.jsonPrimitive?.contentOrNull,
            skxq = obj["skxq"]?.jsonPrimitive?.intOrNull,
            skjc = obj["skjc"]?.jsonPrimitive?.intOrNull,
            cxjc = obj["cxjc"]?.jsonPrimitive?.intOrNull,
            zcsm = obj["zcsm"]?.jsonPrimitive?.contentOrNull,
            kclbmc = obj["kclbmc"]?.jsonPrimitive?.contentOrNull,
            xqm = obj["xqm"]?.jsonPrimitive?.contentOrNull,
            jxlm = obj["jxlm"]?.jsonPrimitive?.contentOrNull,
            jasm = obj["jasm"]?.jsonPrimitive?.contentOrNull,
            mxbj = obj["mxbj"]?.jsonPrimitive?.contentOrNull,
            xss = obj["xss"]?.jsonPrimitive?.intOrNull,
        )
    }

    companion object {
        private const val TAG = "CourseScheduleService"
        const val BASE_URL = "http://jwcxk2-aufe-edu-cn.vpn2.aufe.edu.cn:8118"
        /** 每页记录数；列表滚动到底部才请求下一页 */
        const val PAGE_SIZE = 20
    }
}
