package tech.loveace.appv3.data.service

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.*
import org.jsoup.Jsoup
import tech.loveace.appv3.data.model.*
import tech.loveace.appv3.data.network.AUFEConnection

/**
 * 课程开课查询服务 - 按课程号/学期查询开课情况
 */
class CourseScheduleService(private val connection: AUFEConnection) {

    data class ScheduleTermItem(
        val termCode: String,
        val termName: String,
        val isSelected: Boolean = false,
    )

    suspend fun getScheduleTerms(): UniResponse<List<ScheduleTermItem>> = withContext(Dispatchers.IO) {
        try {
            val url = "$BASE_URL/student/integratedQuery/course/courseSchdule/index"
            val response = connection.client.get(url)
            val html = response.body?.string() ?: throw Exception("响应为空")
            val doc = Jsoup.parse(html)
            val select = doc.selectFirst("select#zxjxjhh")
                ?: doc.selectFirst("select[name=zxjxjhh]")
                ?: throw Exception("未找到学期选择框")
            val options = select.select("option")
            val terms = options.mapNotNull { option ->
                val code = option.attr("value").takeIf { it.isNotEmpty() } ?: return@mapNotNull null
                val name = option.text().trim()
                val selected = option.hasAttr("selected")
                ScheduleTermItem(code, name, selected)
            }
            if (terms.isEmpty()) throw Exception("未能解析出任何学期信息")
            UniResponse.success(terms)
        } catch (e: Exception) {
            Log.e(TAG, "getScheduleTerms failed", e)
            UniResponse.failure(e.message ?: "获取学期列表失败", retryable = true)
        }
    }

    suspend fun queryCourseSchedule(
        courseCode: String,
        termCode: String,
        pageNum: Int = 1,
        pageSize: Int = 50,
    ): UniResponse<List<CourseScheduleRecord>> = withContext(Dispatchers.IO) {
        try {
            val records = fetchPage(termCode, courseCode, pageNum, pageSize).records
            UniResponse.success(records)
        } catch (e: Exception) {
            Log.e(TAG, "queryCourseSchedule failed", e)
            UniResponse.failure(e.message ?: "查询课程开课情况失败", retryable = true)
        }
    }

    suspend fun queryAllCoursesForTerm(
        termCode: String,
        onProgress: ((completed: Int, total: Int, records: Int) -> Unit)? = null,
    ): UniResponse<List<CourseScheduleRecord>> = withContext(Dispatchers.IO) {
        try {
            val pageSize = 200
            val concurrency = 5

            val firstPage = fetchPage(termCode, "", 1, pageSize)
            val allRecords = firstPage.records.toMutableList()
            val totalPages = ((firstPage.totalCount + pageSize - 1) / pageSize).coerceAtLeast(1)
            onProgress?.invoke(1, totalPages, allRecords.size)

            var pageNum = 2
            while (pageNum <= totalPages) {
                val endPage = minOf(pageNum + concurrency - 1, totalPages)
                val batch = (pageNum..endPage).map { p ->
                    async { runCatching { fetchPage(termCode, "", p, pageSize).records }.getOrElse { emptyList() } }
                }
                val results = batch.awaitAll()
                for (result in results) {
                    allRecords.addAll(result)
                }
                onProgress?.invoke(endPage, totalPages, allRecords.size)
                pageNum += concurrency
            }
            UniResponse.success(dedupeRecords(allRecords))
        } catch (e: Exception) {
            Log.e(TAG, "queryAllCoursesForTerm failed", e)
            UniResponse.failure(e.message ?: "查询学期全部开课失败", retryable = true)
        }
    }

    private data class CourseSchedulePage(
        val records: List<CourseScheduleRecord>,
        val totalCount: Int,
    )

    private fun fetchPage(termCode: String, courseCode: String, pageNum: Int, pageSize: Int): CourseSchedulePage {
        val url = "$BASE_URL/student/integratedQuery/course/courseSchdule/courseInfo?sf_request_type=ajax"
        val response = connection.client.post(url, formData = mapOf(
            "zxjxjhh" to termCode, "kch" to courseCode, "kcm" to "",
            "kkxsh" to "", "kkxqh" to "", "jxlh" to "", "jash" to "",
            "skxq" to "", "skjc" to "", "kclb" to "", "skjs" to "",
            "xqname" to "", "jcname" to "", "jxlname" to "", "jasname" to "",
            "pageNum" to pageNum.toString(), "pageSize" to pageSize.toString(),
        ))
        val body = response.body?.string() ?: return CourseSchedulePage(emptyList(), 0)
        val json = Json { ignoreUnknownKeys = true }
        val data = json.parseToJsonElement(body).jsonObject
        val listObj = data["list"]?.jsonObject ?: return CourseSchedulePage(emptyList(), 0)
        val pageContext = listObj["pageContext"]?.jsonObject
        val totalCount = pageContext?.get("totalCount")?.jsonPrimitive?.intOrNull
            ?: listObj["totalCount"]?.jsonPrimitive?.intOrNull
            ?: 0
        val records = listObj["records"]?.jsonArray ?: return CourseSchedulePage(emptyList(), totalCount)
        return CourseSchedulePage(records.mapNotNull { parseCourseScheduleRecord(it.jsonObject) }, totalCount)
    }

    private fun dedupeRecords(records: List<CourseScheduleRecord>): List<CourseScheduleRecord> {
        return records.distinctBy {
            listOf(it.kch, it.kxh, it.skxq, it.skjc, it.cxjc, it.skzc, it.xqm, it.jxlm, it.jasm).joinToString("|")
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
    }
}
