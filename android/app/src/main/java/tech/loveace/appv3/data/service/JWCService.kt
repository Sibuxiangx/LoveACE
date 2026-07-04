package tech.loveace.appv3.data.service

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.*
import org.jsoup.Jsoup
import tech.loveace.appv3.data.model.*
import tech.loveace.appv3.data.network.AUFEConnection

/**
 * 教务系统服务 - 学业信息、成绩、考试、学期、培养方案
 */
class JWCService(private val connection: AUFEConnection) {

    private val termsMutex = Mutex()
    private var cachedTerms: UniResponse<List<TermItem>>? = null
    private var termsCacheTimestamp: Long = 0

    // ==================== Academic Info ====================
    suspend fun getAcademicInfo(): UniResponse<AcademicInfo> = withContext(Dispatchers.IO) {
        try {
            val url = "$BASE_URL/main/academicInfo?sf_request_type=ajax"
            val response = connection.client.post(
                url,
                formData = mapOf("flag" to ""),
                headers = mapOf(
                    "Accept" to "application/json, text/javascript, */*; q=0.01",
                    "X-Requested-With" to "XMLHttpRequest",
                ),
            )
            val body = response.body?.string() ?: throw Exception("响应为空")
            val json = Json.parseToJsonElement(body)
            val arr = json.jsonArray
            if (arr.isEmpty()) throw Exception("数据为空")
            val obj = arr[0].jsonObject
            val info = AcademicInfo(
                completedCourses = obj["courseNum"]?.jsonPrimitive?.intOrNull ?: 0,
                failedCourses = obj["coursePas"]?.jsonPrimitive?.intOrNull ?: 0,
                gpa = obj["gpa"]?.jsonPrimitive?.doubleOrNull ?: 0.0,
                averageScore = obj["sspjf_jd"]?.jsonPrimitive?.doubleOrNull ?: 0.0,
                averageRank = obj["sspjf_pm"]?.jsonPrimitive?.intOrNull ?: 0,
                averageRankTotal = obj["sspjf_rs"]?.jsonPrimitive?.intOrNull ?: 0,
                pendingCourses = obj["courseNum_bxqyxd"]?.jsonPrimitive?.intOrNull ?: 0,
                currentTerm = obj["zxjxjhh"]?.jsonPrimitive?.contentOrNull ?: "",
            )
            UniResponse.success(info)
        } catch (e: Exception) {
            Log.e(TAG, "getAcademicInfo failed", e)
            UniResponse.failure(e.message ?: "获取学业信息失败", retryable = true)
        }
    }

    // ==================== Terms ====================
    suspend fun getAllTerms(): UniResponse<List<TermItem>> = termsMutex.withLock {
        val now = System.currentTimeMillis()
        val cached = cachedTerms
        if (cached?.success == true && now - termsCacheTimestamp < CACHE_TTL_MS) {
            Log.d(TAG, "Cache hit for terms")
            return@withLock cached
        }

        val result = withContext(Dispatchers.IO) {
            try {
                val url = "$BASE_URL/student/courseSelect/calendarSemesterCurriculum/index"
                val response = connection.client.get(url)
                val html = response.body?.string() ?: throw Exception("响应为空")
                val doc = Jsoup.parse(html)
                val select = doc.selectFirst("select#planCode") ?: throw Exception("未找到学期选择框")
                val options = select.select("option")
                val parsedTerms = options.mapNotNull { option ->
                    val code = option.attr("value").takeIf { it.isNotEmpty() } ?: return@mapNotNull null
                    val rawName = option.text().trim()
                    val name = rawName.replace("春", "下").replace("秋", "上")
                    val isCurrent = option.hasAttr("selected") || rawName.contains("当前")
                    TermItem(termCode = code, termName = name, isCurrent = isCurrent)
                }
                val terms = if (parsedTerms.any { it.isCurrent }) {
                    parsedTerms
                } else {
                    parsedTerms.mapIndexed { index, term ->
                        if (index == 0) term.copy(isCurrent = true) else term
                    }
                }
                UniResponse.success(terms)
            } catch (e: Exception) {
                Log.e(TAG, "getAllTerms failed", e)
                UniResponse.failure(e.message ?: "获取学期列表失败", retryable = true)
            }
        }

        if (result.success) {
            cachedTerms = result
            termsCacheTimestamp = System.currentTimeMillis()
        }

        result
    }

    // ==================== Scores ====================
    suspend fun getTermScore(termCode: String): UniResponse<TermScoreResponse> = withContext(Dispatchers.IO) {
        try {
            // Step 1: Get dynamic path
            val preUrl = "$BASE_URL/student/integratedQuery/scoreQuery/allTermScores/index"
            val preResponse = connection.client.get(preUrl)
            val preHtml = preResponse.body?.string() ?: throw Exception("页面为空")
            val pathMatch = Regex("/([A-Za-z0-9]+)/allTermScores/data").find(preHtml)
                ?: throw Exception("未能提取动态路径")
            val dynamicPath = pathMatch.groupValues[1]

            // Step 2: Fetch scores
            val scoreUrl = "$BASE_URL/student/integratedQuery/scoreQuery/$dynamicPath/allTermScores/data"
            val scoreResponse = connection.client.post(
                scoreUrl,
                formData = mapOf(
                    "zxjxjhh" to termCode, "kch" to "", "kcm" to "",
                    "pageNum" to "1", "pageSize" to "100", "sf_request_type" to "ajax",
                ),
                headers = mapOf("Referer" to preUrl),
            )
            val body = scoreResponse.body?.string() ?: throw Exception("成绩数据为空")
            val json = Json.parseToJsonElement(body).jsonObject
            val listData = json["list"]?.jsonObject ?: return@withContext UniResponse.success(
                TermScoreResponse(0, emptyList())
            )
            val recordsArr = listData["records"]?.jsonArray ?: return@withContext UniResponse.success(
                TermScoreResponse(0, emptyList())
            )
            val records = recordsArr.mapNotNull { parseScoreRecord(it.jsonArray) }
            val total = listData["pageContext"]?.jsonObject?.get("totalCount")?.jsonPrimitive?.intOrNull ?: records.size
            UniResponse.success(TermScoreResponse(total, records))
        } catch (e: Exception) {
            Log.e(TAG, "getTermScore failed", e)
            UniResponse.failure(e.message ?: "获取成绩失败", retryable = true)
        }
    }

    private fun parseScoreRecord(arr: JsonArray): ScoreRecord? {
        if (arr.size < 11) return null
        return ScoreRecord(
            sequence = arr[0].jsonPrimitive.intOrNull ?: 0,
            termId = arr[1].jsonPrimitive.contentOrNull ?: "",
            courseCode = arr[2].jsonPrimitive.contentOrNull ?: "",
            courseClass = arr[3].jsonPrimitive.contentOrNull ?: "",
            courseNameCn = arr[4].jsonPrimitive.contentOrNull ?: "",
            courseNameEn = arr[5].jsonPrimitive.contentOrNull ?: "",
            credits = arr[6].jsonPrimitive.contentOrNull ?: "0",
            hours = arr[7].jsonPrimitive.contentOrNull?.toIntOrNull() ?: 0,
            courseType = arr.getOrNull(8)?.jsonPrimitive?.contentOrNull,
            examType = arr.getOrNull(9)?.jsonPrimitive?.contentOrNull,
            score = arr[10].jsonPrimitive.contentOrNull ?: "",
            retakeScore = arr.getOrNull(11)?.jsonPrimitive?.contentOrNull,
            makeupScore = arr.getOrNull(12)?.jsonPrimitive?.contentOrNull,
        )
    }

    // ==================== Exams ====================
    suspend fun getExamInfo(): UniResponse<List<UnifiedExamInfo>> = withContext(Dispatchers.IO) {
        try {
            val academicResp = getAcademicInfo()
            if (!academicResp.success || academicResp.data == null) throw Exception("无法获取学期信息")
            val termCode = academicResp.data.currentTerm
            val now = java.time.LocalDate.now()
            val startDate = now.toString()
            val endDate = if (termCode.endsWith("1")) "${now.year + 1}-03-30" else "${now.year}-09-30"

            // Fetch school exams
            val preUrl = "$BASE_URL/student/examinationManagement/examPlan/index"
            val preResp = connection.client.get(preUrl)
            val preHtml = preResp.body?.string() ?: ""
            val seatInfos = parseExamSeatInfo(preHtml)
            val ts = System.currentTimeMillis()
            val examUrl = "$BASE_URL/student/examinationManagement/examPlan/detail?start=$startDate&end=$endDate&_=$ts"
            val examResp = connection.client.get(examUrl, headers = mapOf(
                "Accept" to "application/json, text/javascript, */*; q=0.01",
                "X-Requested-With" to "XMLHttpRequest",
            ))
            val examBody = examResp.body?.string() ?: "[]"
            val schoolExams = if (examBody.trim() == "]" || examBody.isBlank()) emptyList()
            else try {
                Json.parseToJsonElement(examBody).jsonArray.mapNotNull { parseSchoolExam(it.jsonObject, seatInfos) }
            } catch (_: Exception) { emptyList() }

            // Fetch other exams
            val otherUrl = "$BASE_URL/student/examinationManagement/othersExamPlan/queryScores?sf_request_type=ajax"
            val otherResp = connection.client.post(otherUrl, formData = mapOf(
                "zxjxjhh" to termCode, "tab" to "0", "pageNum" to "1", "pageSize" to "30",
            ))
            val otherBody = otherResp.body?.string() ?: "{}"
            val otherExams = try {
                val json = Json.parseToJsonElement(otherBody).jsonObject
                val records = json["records"]?.jsonArray
                    ?: json["list"]?.jsonObject?.get("records")?.jsonArray
                    ?: JsonArray(emptyList())
                records.mapNotNull { parseOtherExam(it) }
            } catch (_: Exception) { emptyList() }

            val all = (schoolExams + otherExams).sortedWith(compareBy({ it.examDate }, { it.examTime }))
            UniResponse.success(all)
        } catch (e: Exception) {
            Log.e(TAG, "getExamInfo failed", e)
            UniResponse.failure(e.message ?: "获取考试信息失败", retryable = true)
        }
    }

    private data class ExamSeatInfo(val courseName: String, val seatNumber: String)

    private fun parseExamSeatInfo(html: String): List<ExamSeatInfo> {
        if (html.isBlank()) return emptyList()
        val doc = Jsoup.parse(html)
        return doc.select("div.widget-box").mapNotNull { box ->
            val titleElement = box.selectFirst("h5.widget-title") ?: return@mapNotNull null
            val mainElement = box.selectFirst("div.widget-main") ?: return@mapNotNull null
            val courseTitle = titleElement.text().trim()
            val courseName = Regex("[）)](.+)$").find(courseTitle)?.groupValues?.get(1)?.trim() ?: courseTitle
            val seatNumber = Regex("座位号[：:](.+?)(?:准考证号|$)")
                .find(mainElement.text().trim())
                ?.groupValues
                ?.get(1)
                ?.trim()
                ?: return@mapNotNull null

            if (seatNumber.isEmpty()) null else ExamSeatInfo(courseName, seatNumber)
        }
    }

    private fun parseSchoolExam(obj: JsonObject, seatInfos: List<ExamSeatInfo>): UnifiedExamInfo? {
        val title = obj["title"]?.jsonPrimitive?.contentOrNull ?: return null
        val lines = title.split("\n").map { it.trim() }
        val courseName = lines.getOrElse(0) { "" }
        val seatNumber = seatInfos.firstOrNull { it.courseName == courseName }?.seatNumber.orEmpty()
        return UnifiedExamInfo(
            courseName = courseName,
            examDate = obj["start"]?.jsonPrimitive?.contentOrNull ?: "",
            examTime = lines.getOrElse(1) { "" },
            examLocation = lines.drop(2).joinToString(" "),
            examType = "校统考",
            note = if (seatNumber.isEmpty()) "" else "座位号: $seatNumber",
        )
    }

    private fun parseOtherExam(element: JsonElement): UnifiedExamInfo? = when (element) {
        is JsonArray -> parseOtherExamArray(element)
        is JsonObject -> parseOtherExamObject(element)
        else -> null
    }

    private fun parseOtherExamArray(arr: JsonArray): UnifiedExamInfo? {
        if (arr.size < 8) return null
        return UnifiedExamInfo(
            courseName = arr[2].jsonPrimitive.contentOrNull ?: "",
            examDate = arr[4].jsonPrimitive.contentOrNull ?: "",
            examTime = arr[5].jsonPrimitive.contentOrNull ?: "",
            examLocation = arr[6].jsonPrimitive.contentOrNull ?: "",
            examType = "其他考试",
            note = arr.getOrNull(7)?.jsonPrimitive?.contentOrNull ?: "",
        )
    }

    private fun parseOtherExamObject(obj: JsonObject): UnifiedExamInfo? {
        val courseName = obj.string("KCM")
        val examDate = obj.string("KSRQ")
        val examTime = obj.string("KSSJ")
        if (courseName.isEmpty() && examDate.isEmpty() && examTime.isEmpty()) return null
        return UnifiedExamInfo(
            courseName = courseName,
            examDate = examDate,
            examTime = examTime,
            examLocation = obj.string("KSDD"),
            examType = "其他考试",
            note = obj.string("BZ"),
        )
    }

    // ==================== Training Plan ====================
    suspend fun getTrainingPlanInfo(): UniResponse<TrainingPlanInfo> = withContext(Dispatchers.IO) {
        try {
            val url = "$BASE_URL/main/showPyfaInfo?sf_request_type=ajax"
            val response = connection.client.get(url)
            val body = response.body?.string() ?: throw Exception("响应为空")
            val json = Json.parseToJsonElement(body).jsonObject
            val dataList = json["data"]?.jsonArray ?: throw Exception("无培养方案数据")
            val planArr = dataList[0].jsonArray
            val planName = planArr[0].jsonPrimitive.content
            val gradeMatch = Regex("(\\d{4})级").find(planName)
            val grade = gradeMatch?.groupValues?.get(1) ?: ""
            val majorName = planName.replace(Regex("\\d{4}级"), "")
                .replace("本科培养方案", "").replace("培养方案", "").trim()
            UniResponse.success(TrainingPlanInfo(planName, majorName, grade))
        } catch (e: Exception) {
            Log.e(TAG, "getTrainingPlanInfo failed", e)
            UniResponse.failure(e.message ?: "获取培养方案失败", retryable = true)
        }
    }

    companion object {
        private const val TAG = "JWCService"
        private const val CACHE_TTL_MS = 30_000L
        const val BASE_URL = "http://jwcxk2-aufe-edu-cn.vpn2.aufe.edu.cn:8118"
    }
}

private fun JsonObject.string(key: String): String = this[key]?.jsonPrimitive?.contentOrNull ?: ""
