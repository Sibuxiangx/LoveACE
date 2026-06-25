package tech.loveace.appv3.data.service

import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.jsoup.Jsoup
import org.jsoup.nodes.Document
import org.jsoup.nodes.Element
import tech.loveace.appv3.data.model.TeacherEvaluationCourse
import tech.loveace.appv3.data.model.TeacherEvaluationCourseList
import tech.loveace.appv3.data.model.TeacherEvaluationIndex
import tech.loveace.appv3.data.model.TeacherEvaluationOption
import tech.loveace.appv3.data.model.TeacherEvaluationPreparedForm
import tech.loveace.appv3.data.model.TeacherEvaluationQuestionnaire
import tech.loveace.appv3.data.model.TeacherEvaluationRadioQuestion
import tech.loveace.appv3.data.model.TeacherEvaluationSubmitResult
import tech.loveace.appv3.data.model.TeacherEvaluationTextQuestion
import tech.loveace.appv3.data.model.TeacherEvaluationTextType
import tech.loveace.appv3.data.model.UniResponse
import tech.loveace.appv3.data.network.AUFEConnection
import kotlin.random.Random

enum class EvaluationStrategy {
    Smart,
    AlwaysHighest
}

class TeacherEvaluationService(private val connection: AUFEConnection) {

    suspend fun loadCourses(): UniResponse<TeacherEvaluationCourseList> = withContext(Dispatchers.IO) {
        try {
            val index = fetchIndexInternal()
            if (index.isClosed) {
                return@withContext UniResponse.success(
                    TeacherEvaluationCourseList(
                        tokenValue = index.tokenValue,
                        isClosed = true,
                        closedMessage = index.closedMessage.ifBlank { "评价暂未开启" },
                    )
                )
            }
            if (index.tokenValue.isBlank()) throw Exception("未找到评教 token")
            UniResponse.success(
                TeacherEvaluationCourseList(
                    tokenValue = index.tokenValue,
                    isClosed = false,
                    courses = fetchCoursesInternal(),
                )
            )
        } catch (e: Exception) {
            Log.e(TAG, "loadCourses failed", e)
            UniResponse.failure(e.message ?: "获取评教课程失败", retryable = true)
        }
    }

    suspend fun prepareEvaluation(
        course: TeacherEvaluationCourse,
        pendingCount: Int,
        indexToken: String,
        strategy: EvaluationStrategy = EvaluationStrategy.Smart,
    ): UniResponse<TeacherEvaluationPreparedForm> = withContext(Dispatchers.IO) {
        try {
            if (indexToken.isBlank()) throw Exception("首页 token 为空")
            val html = connection.client.post(
                "$BASE_URL/student/teachingEvaluation/teachingEvaluation/evaluationPage",
                formData = evaluationPageForm(course, pendingCount, indexToken),
                headers = ajaxHeaders(),
            ).use { response ->
                if (!response.isSuccessful) throw Exception("评价页 HTTP ${response.code}")
                response.body?.string() ?: throw Exception("评价页响应为空")
            }

            val questionnaire = parseQuestionnaire(html)
            if (questionnaire.tokenValue.isBlank()) throw Exception("未找到评价页 token")
            if (questionnaire.radioQuestions.isEmpty() && questionnaire.textQuestions.isEmpty()) {
                throw Exception("未解析到评价题目")
            }

            val form = linkedMapOf(
                "optType" to "submit",
                "tokenValue" to questionnaire.tokenValue,
                "questionnaireCode" to course.questionnaireCode.ifBlank { questionnaire.questionnaireCode },
                "evaluationContent" to course.evaluationContentNumber.ifBlank { questionnaire.evaluationContent },
                "evaluatedPeopleNumber" to course.evaluatedPeopleNumber.ifBlank { questionnaire.evaluatedPeopleNumber },
                "count" to pendingCount.toString(),
            )

            questionnaire.radioQuestions.forEach { question ->
                form[question.key] = chooseOption(question, strategy).value
            }
            questionnaire.textQuestions.forEach { question ->
                form[question.key] = randomText(question.type)
            }

            UniResponse.success(
                TeacherEvaluationPreparedForm(
                    course = course,
                    questionnaireTitle = questionnaire.title,
                    formData = form,
                )
            )
        } catch (e: Exception) {
            Log.e(TAG, "prepareEvaluation failed", e)
            UniResponse.failure(e.message ?: "准备评价表单失败", retryable = true)
        }
    }

    suspend fun submitEvaluation(prepared: TeacherEvaluationPreparedForm): UniResponse<TeacherEvaluationSubmitResult> = withContext(Dispatchers.IO) {
        try {
            val body = connection.client.post(
                "$BASE_URL/student/teachingEvaluation/teachingEvaluation/assessment?sf_request_type=ajax",
                formData = prepared.formData,
                headers = ajaxHeaders(),
            ).use { response ->
                response.body?.string() ?: throw Exception("提交响应为空")
            }
            val json = runCatching { Json.parseToJsonElement(body).jsonObject }.getOrNull()
            val result = json?.string("result").orEmpty()
            val msg = json?.string("msg").orEmpty().ifBlank {
                if (result.equals("success", ignoreCase = true)) {
                    "提交成功"
                } else if (json != null) {
                    "提交失败，服务端返回错误"
                } else {
                    body.take(120)
                }
            }
            UniResponse.success(
                TeacherEvaluationSubmitResult(
                    success = result.equals("success", ignoreCase = true),
                    message = msg,
                )
            )
        } catch (e: Exception) {
            Log.e(TAG, "submitEvaluation failed", e)
            UniResponse.failure(e.message ?: "提交评价失败", retryable = true)
        }
    }

    suspend fun verifyCourseEvaluated(course: TeacherEvaluationCourse): UniResponse<Boolean> = withContext(Dispatchers.IO) {
        try {
            val courseList = loadCourses()
            if (!courseList.success || courseList.data == null) {
                return@withContext UniResponse.failure(courseList.error ?: "刷新课程列表失败", retryable = true)
            }
            val refreshedCourse = courseList.data.courses.firstOrNull { it.matches(course) }
            UniResponse.success(refreshedCourse?.isEvaluated == true)
        } catch (e: Exception) {
            Log.e(TAG, "verifyCourseEvaluated failed", e)
            UniResponse.failure(e.message ?: "验证评教状态失败", retryable = true)
        }
    }

    private fun fetchIndexInternal(): TeacherEvaluationIndex {
        val html = connection.client.get(
            "$BASE_URL/student/teachingEvaluation/evaluation/index",
            headers = pageHeaders(),
        ).use { response ->
            response.body?.string() ?: throw Exception("首页响应为空")
        }
        val doc = Jsoup.parse(html)
        val alert = doc.select("#page-content-template .alert, .page-content .alert, .main-content .alert")
            .firstOrNull { it.text().contains("评估开关已关闭") }
        return TeacherEvaluationIndex(
            tokenValue = parseTokenValue(doc, html),
            isClosed = alert != null,
            closedMessage = alert?.text()?.trim().orEmpty(),
        )
    }

    private fun fetchCoursesInternal(): List<TeacherEvaluationCourse> {
        val body = connection.client.post(
            "$BASE_URL/student/teachingEvaluation/teachingEvaluation/search?sf_request_type=ajax",
            formData = mapOf("optType" to "1", "pagesize" to "50"),
            headers = ajaxHeaders(),
        ).use { response ->
            response.body?.string() ?: throw Exception("课程列表响应为空")
        }
        val root = Json.parseToJsonElement(body).jsonObject
        val data = root["data"]?.jsonArrayOrNull() ?: JsonArray(emptyList())
        return data.mapNotNull { parseCourse(it.jsonObjectOrNull()) }
    }

    private fun parseCourse(obj: JsonObject?): TeacherEvaluationCourse? {
        if (obj == null) return null
        val id = obj["id"].jsonObjectOrNull()
        val questionnaire = obj["questionnaire"].jsonObjectOrNull()
        val course = TeacherEvaluationCourse(
            name = obj.string("evaluationContent"),
            teacher = obj.string("evaluatedPeople"),
            evaluatedPeople = obj.string("evaluatedPeople"),
            evaluatedPeopleNumber = id.string("evaluatedPeople"),
            coureSequenceNumber = id.string("coureSequenceNumber"),
            evaluationContentNumber = id.string("evaluationContentNumber"),
            questionnaireCode = questionnaire.string("questionnaireNumber"),
            questionnaireName = questionnaire.string("questionnaireName"),
            isEvaluated = obj.string("isEvaluated") == "是",
        )
        return course.takeIf {
            it.name.isNotBlank() || it.teacher.isNotBlank() || it.evaluationContentNumber.isNotBlank()
        }
    }

    private fun evaluationPageForm(
        course: TeacherEvaluationCourse,
        pendingCount: Int,
        indexToken: String,
    ): Map<String, String> = linkedMapOf(
        "count" to pendingCount.toString(),
        "evaluatedPeople" to course.evaluatedPeople,
        "evaluatedPeopleNumber" to course.evaluatedPeopleNumber,
        "questionnaireCode" to course.questionnaireCode,
        "questionnaireName" to course.questionnaireName,
        "coureSequenceNumber" to course.coureSequenceNumber,
        "evaluationContentNumber" to course.evaluationContentNumber,
        "evaluationContentContent" to "",
        "tokenValue" to indexToken,
    )

    private fun parseQuestionnaire(html: String): TeacherEvaluationQuestionnaire {
        val doc = Jsoup.parse(html)
        return TeacherEvaluationQuestionnaire(
            title = doc.selectFirst("div.title")?.text()?.trim()
                ?: doc.selectFirst("h1")?.text()?.trim()
                ?: doc.selectFirst("h2")?.text()?.trim()
                ?: "",
            tokenValue = parseQuestionnaireTokenValue(doc, html),
            questionnaireCode = doc.inputValue("wjdm"),
            evaluatedPeopleNumber = doc.inputValue("bprdm"),
            evaluationContent = doc.inputValue("pgnr"),
            evaluatedPerson = doc.select("td")
                .firstOrNull { it.text().contains("被评人") || it.text().contains("教师") }
                ?.nextElementSibling()?.text()?.trim().orEmpty(),
            radioQuestions = parseRadioQuestions(doc),
            textQuestions = parseTextQuestions(doc),
        )
    }

    private fun parseRadioQuestions(doc: Document): List<TeacherEvaluationRadioQuestion> {
        return doc.select("input[type=radio][name]")
            .groupBy { it.attr("name") }
            .mapNotNull { (name, radios) ->
                if (name.isBlank()) return@mapNotNull null
                val firstRadio = radios.firstOrNull() ?: return@mapNotNull null
                val row = firstRadio.nearestRow()
                val options = radios.mapNotNull { radio ->
                    val value = radio.attr("value").takeIf { it.isNotBlank() } ?: return@mapNotNull null
                    val scoreAndWeight = value.scoreAndWeight()
                    TeacherEvaluationOption(
                        key = name,
                        value = value,
                        score = scoreAndWeight.first,
                        weight = scoreAndWeight.second,
                        label = radio.optionLabel(doc),
                    )
                }
                if (options.isEmpty()) return@mapNotNull null
                TeacherEvaluationRadioQuestion(
                    key = name,
                    category = row?.selectFirst("td[rowspan]")?.text()?.trim().orEmpty(),
                    title = row.questionText(minLength = 5, selectorToExclude = "input[type=radio]")
                        .ifBlank { row.previousRowText(minLength = 5) },
                    options = options,
                )
            }
    }

    private fun parseTextQuestions(doc: Document): List<TeacherEvaluationTextQuestion> {
        return doc.select("textarea[name]").mapNotNull { textarea ->
            val name = textarea.attr("name").takeIf { it.isNotBlank() } ?: return@mapNotNull null
            val td = textarea.parents().firstOrNull { it.tagName().equals("td", ignoreCase = true) }
            val row = textarea.nearestRow()
            val title = td?.previousElementSibling()?.text()?.trim()?.takeIf { it.isNotBlank() }
                ?: td?.ownText()?.trim()?.takeIf { it.length > 3 }
                ?: td?.text()?.trim()?.takeIf { it.length > 3 }
                ?: row.previousRowText(minLength = 3)
            val required = name == "zgpj" || name.contains("zgpj")
            TeacherEvaluationTextQuestion(
                key = name,
                title = title,
                required = required,
                type = textType(name, title),
            )
        }
    }

    private fun chooseOption(question: TeacherEvaluationRadioQuestion, strategy: EvaluationStrategy): TeacherEvaluationOption {
        val options = question.options.sortedByDescending { it.weight }
        // 一键非常满意：强制选最高权重
        if (strategy == EvaluationStrategy.AlwaysHighest) {
            val fullWeightOptions = options.filter { it.weight == 1.0 }
            if (fullWeightOptions.isNotEmpty()) {
                return fullWeightOptions.random()
            }
            return options.first()
        }
        val fullWeightOptions = options.filter { it.weight == 1.0 }
        if (fullWeightOptions.isNotEmpty() && Random.nextDouble() < 0.8) {
            return fullWeightOptions.random()
        }
        val weightGroups = options.groupBy { it.weight }.entries.sortedByDescending { it.key }
        val secondGroup = if (fullWeightOptions.isNotEmpty()) {
            weightGroups.firstOrNull { it.key != 1.0 }?.value
        } else {
            null
        }
        return (secondGroup ?: weightGroups.first().value).random()
    }

    private fun randomText(type: TeacherEvaluationTextType): String {
        val pool = when (type) {
            TeacherEvaluationTextType.Inspiration -> inspirationTexts
            TeacherEvaluationTextType.Suggestion -> suggestionTexts
            TeacherEvaluationTextType.Overall,
            TeacherEvaluationTextType.General -> overallTexts
        }
        var last = ""
        repeat(3) {
            last = pool.random().sanitizeAnswer()
            if (last.isValidAnswer()) return last
        }
        return last
    }

    private fun textType(name: String, title: String): TeacherEvaluationTextType = when {
        name == "zgpj" || name.contains("zgpj") -> TeacherEvaluationTextType.Overall
        title.contains("启发") || title.contains("启示") -> TeacherEvaluationTextType.Inspiration
        title.contains("建议") || title.contains("意见") || title.contains("改进") -> TeacherEvaluationTextType.Suggestion
        else -> TeacherEvaluationTextType.General
    }

    private fun parseTokenValue(doc: Document, html: String): String {
        return doc.selectFirst("input#tokenValue")?.attr("value")?.takeIf { it.isNotBlank() }
            ?: doc.selectFirst("input[name=tokenValue]")?.attr("value")?.takeIf { it.isNotBlank() }
            ?: TOKEN_REGEX.find(html)?.groupValues?.getOrNull(1).orEmpty()
    }

    private fun parseQuestionnaireTokenValue(doc: Document, html: String): String {
        return doc.selectFirst("input[name=tokenValue]")?.attr("value")?.takeIf { it.isNotBlank() }
            ?: doc.selectFirst("input#tokenValue")?.attr("value")?.takeIf { it.isNotBlank() }
            ?: TOKEN_REGEX.find(html)?.groupValues?.getOrNull(1).orEmpty()
    }

    private fun Document.inputValue(name: String): String = selectFirst("input[name=$name]")?.attr("value").orEmpty()

    private fun Element?.questionText(minLength: Int, selectorToExclude: String): String {
        if (this == null) return ""
        return select("td").firstOrNull { cell ->
            cell.select(selectorToExclude).isEmpty() && cell.text().trim().length > minLength
        }?.text()?.trim().orEmpty()
    }

    private fun Element?.previousRowText(minLength: Int): String {
        var previous = this?.previousElementSibling()
        while (previous != null) {
            if (previous.tagName().equals("tr", ignoreCase = true)) {
                val text = previous.select("td").firstOrNull { it.text().trim().length > minLength }
                    ?.text()?.trim().orEmpty()
                if (text.isNotBlank()) return text
            }
            previous = previous.previousElementSibling()
        }
        return ""
    }

    private fun Element.nearestRow(): Element? = parents().firstOrNull { it.tagName().equals("tr", ignoreCase = true) }

    private fun Element.optionLabel(doc: Document): String {
        val id = id()
        if (id.isNotBlank()) {
            doc.select("label").firstOrNull { it.attr("for") == id }?.text()?.trim()?.takeIf { it.isNotBlank() }
                ?.let { return it }
        }
        parent()?.takeIf { it.tagName().equals("label", ignoreCase = true) }?.text()?.trim()?.takeIf { it.isNotBlank() }
            ?.let { return it }
        return parents().firstOrNull { it.tagName().equals("td", ignoreCase = true) }?.text()?.trim().orEmpty()
    }

    private fun String.scoreAndWeight(): Pair<Double, Double> {
        val parts = split("_")
        val score = parts.getOrNull(0)?.toDoubleOrNull() ?: 0.0
        val weight = parts.getOrNull(1)?.toDoubleOrNull() ?: 0.0
        return score to weight
    }

    private fun String.sanitizeAnswer(): String = replace(Regex("\\s+"), "")

    private fun String.isValidAnswer(): Boolean = length >= 4 && !Regex("(.)\\1\\1").containsMatchIn(this)

    private fun JsonObject?.string(key: String): String = this?.get(key)?.stringValue().orEmpty()

    private fun JsonElement?.jsonObjectOrNull(): JsonObject? = runCatching { this?.jsonObject }.getOrNull()

    private fun JsonElement?.jsonArrayOrNull(): JsonArray? = runCatching { this?.jsonArray }.getOrNull()

    private fun JsonElement?.stringValue(): String = runCatching { this?.jsonPrimitive?.contentOrNull }.getOrNull().orEmpty()

    private fun pageHeaders() = mapOf("User-Agent" to MOBILE_SAFARI_UA)

    private fun ajaxHeaders() = mapOf(
        "Accept" to "application/json, text/javascript, */*; q=0.01",
        "X-Requested-With" to "XMLHttpRequest",
        "User-Agent" to MOBILE_SAFARI_UA,
    )

    companion object {
        private const val TAG = "TeacherEvaluationService"
        private const val BASE_URL = "http://jwcxk2-aufe-edu-cn.vpn2.aufe.edu.cn:8118"
        private const val MOBILE_SAFARI_UA =
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        private val TOKEN_REGEX = Regex("""(?:id|name)=["']tokenValue["'][^>]*value=["']([^"']+)["']""")

        private val overallTexts = listOf(
            "老师授课有条理有重点，教会我做事要分清主次、抓住关键的思维方法",
            "老师讲课认真负责，课程内容充实丰富，理论与实践结合得很好，让我收获颇丰，对专业知识有了更深入的理解",
            "老师教学认真细致，课堂安排合理，知识点讲解清楚，能够结合实际帮助我们理解课程内容",
            "课程内容讲解清晰，老师备课充分，课堂节奏适中，整体学习体验很好，收获也比较明显",
        )
        private val inspirationTexts = listOf(
            "课程内容对我很有启发，帮助我从不同角度理解专业问题，也提升了分析和解决问题的能力",
            "老师的讲解让我对课程知识有了新的认识，课堂案例也启发我把理论和实际问题联系起来思考",
            "这门课让我收获很多，不仅理解了知识点，也学会了更有条理地分析问题和表达自己的观点",
        )
        private val suggestionTexts = listOf(
            "老师讲课很好，很认真负责，我没有什么建议，希望老师继续保持现有的教学方式",
            "整体教学效果很好，建议后续可以适当增加课堂互动和案例拓展，帮助同学进一步巩固理解",
            "目前课程安排比较合理，没有明显建议，希望继续保持认真负责的教学态度和清晰的讲解方式",
        )
    }
}
