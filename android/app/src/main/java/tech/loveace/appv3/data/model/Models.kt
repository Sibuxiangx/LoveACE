package tech.loveace.appv3.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// ==================== UniResponse ====================
data class UniResponse<T>(
    val success: Boolean,
    val data: T? = null,
    val message: String = "",
    val error: String? = null,
    val retryable: Boolean = false,
) {
    companion object {
        fun <T> success(data: T, message: String = "操作成功") =
            UniResponse(success = true, data = data, message = message)

        fun <T> failure(error: String, message: String = "操作失败", retryable: Boolean = false) =
            UniResponse<T>(success = false, message = message, error = error, retryable = retryable)
    }
}

// ==================== JWC Models ====================
@Serializable
data class AcademicInfo(
    @SerialName("courseNum") val completedCourses: Int = 0,
    @SerialName("coursePas") val failedCourses: Int = 0,
    @SerialName("gpa") val gpa: Double = 0.0,
    @SerialName("sspjf_jd") val averageScore: Double = 0.0,
    @SerialName("sspjf_pm") val averageRank: Int = 0,
    @SerialName("sspjf_rs") val averageRankTotal: Int = 0,
    @SerialName("courseNum_bxqyxd") val pendingCourses: Int = 0,
    @SerialName("zxjxjhh") val currentTerm: String = "",
) {
    val hasAverageRank: Boolean get() = averageRank > 0 && averageRankTotal > 0
    val averageRankProgress: Float
        get() = if (hasAverageRank) (1f - (averageRank - 1).toFloat() / averageRankTotal).coerceIn(0f, 1f) else 0f
}

@Serializable
data class TermItem(
    val termCode: String,
    val termName: String,
    val isCurrent: Boolean = false,
)

@Serializable
data class ScoreRecord(
    val sequence: Int = 0,
    val termId: String = "",
    val courseCode: String = "",
    val courseClass: String = "",
    val courseNameCn: String = "",
    val courseNameEn: String = "",
    val credits: String = "0",
    val hours: Int = 0,
    val courseType: String? = null,
    val examType: String? = null,
    val score: String = "",
    val retakeScore: String? = null,
    val makeupScore: String? = null,
    val examTime: String = "",
)

val ScoreRecord.hasPublishedScore: Boolean
    get() = score.isNotBlank()

@Serializable
data class ScoreDetailItem(
    val scoreType: String = "",
    val usualScore: String = "",
    val midtermScore: String = "",
    val finalScore: String = "",
    val categoryScore: String = "",
    val remark: String = "",
)

@Serializable
data class ScoreDetail(
    val items: List<ScoreDetailItem> = emptyList(),
)

@Serializable
data class TermScoreResponse(
    val totalCount: Int = 0,
    val records: List<ScoreRecord> = emptyList(),
)

@Serializable
data class UnifiedExamInfo(
    val courseName: String = "",
    val examDate: String = "",
    val examTime: String = "",
    val examLocation: String = "",
    val examType: String = "",
    val note: String = "",
)

@Serializable
data class TrainingPlanInfo(
    val planName: String = "",
    val majorName: String = "",
    val grade: String = "",
)

// ==================== YKT Models ====================
@Serializable
data class CardBalance(
    val balance: Double = 0.0,
    val balanceText: String = "",
)

@Serializable
data class TransactionRecord(
    val accountingTime: String = "",
    val transactionTime: String = "",
    val expense: Double? = null,
    val income: Double? = null,
    val operationType: String = "",
    val balance: Double = 0.0,
    val area: String = "",
    val terminalId: String = "",
) {
    val isExpense get() = expense != null && expense > 0
    val isIncome get() = income != null && income > 0
    val amount get() = if (isIncome) income!! else -(expense ?: 0.0)
    val amountText: String
        get() = when {
            isIncome -> "+${"%.2f".format(income)}元"
            isExpense -> "-${"%.2f".format(expense)}元"
            else -> "0.00元"
        }
}

// ==================== ISIM Models ====================
@Serializable
data class ElectricityBalance(
    val remainingPurchased: Double = 0.0,
    val remainingSubsidy: Double = 0.0,
) {
    val total get() = remainingPurchased + remainingSubsidy
}

@Serializable
data class ElectricityUsageRecord(
    val recordTime: String = "",
    val usageAmount: Double = 0.0,
    val meterName: String = "",
)

@Serializable
data class PaymentRecord(
    val paymentTime: String = "",
    val amount: Double = 0.0,
    val paymentType: String = "",
)

@Serializable
data class ElectricityInfo(
    val balance: ElectricityBalance = ElectricityBalance(),
    val usageRecords: List<ElectricityUsageRecord> = emptyList(),
    val payments: List<PaymentRecord> = emptyList(),
)

// ==================== AAC Models ====================
@Serializable
data class AACCreditInfo(
    @SerialName("TotalScore") val totalScore: Double = 0.0,
    @SerialName("IsTypeAdopt") val isTypeAdopt: Boolean = false,
    @SerialName("TypeAdoptResult") val typeAdoptResult: String = "",
)

@Serializable
data class AACCreditItem(
    @SerialName("ID") val id: String = "",
    @SerialName("Title") val title: String = "",
    @SerialName("TypeName") val typeName: String = "",
    @SerialName("UserNo") val userNo: String = "",
    @SerialName("Score") val score: Double = 0.0,
    @SerialName("AddTime") val addTime: String = "",
)

@Serializable
data class AACCreditCategory(
    @SerialName("ID") val id: String = "",
    @SerialName("ShowNum") val showNum: Int = 0,
    @SerialName("TypeName") val typeName: String = "",
    @SerialName("TotalScore") val totalScore: Double = 0.0,
    @SerialName("children") val children: List<AACCreditItem> = emptyList(),
)

// ==================== Competition Models ====================
@Serializable
data class AwardProject(
    val projectId: String = "",
    val projectName: String = "",
    val level: String = "",
    val grade: String = "",
    val awardDate: String = "",
    val applicantId: String = "",
    val applicantName: String = "",
    val order: Int = 0,
    val credits: Double = 0.0,
    val bonus: Double = 0.0,
    val status: String = "",
    val verificationStatus: String = "",
)

@Serializable
data class CreditsSummary(
    val disciplineCompetitionCredits: Double? = null,
    val scientificResearchCredits: Double? = null,
    val transferableCompetitionCredits: Double? = null,
    val innovationPracticeCredits: Double? = null,
    val abilityCertificationCredits: Double? = null,
    val otherProjectCredits: Double? = null,
) {
    val totalCredits: Double
        get() = listOfNotNull(
            disciplineCompetitionCredits, scientificResearchCredits,
            transferableCompetitionCredits, innovationPracticeCredits,
            abilityCertificationCredits, otherProjectCredits
        ).sum()
}

@Serializable
data class CompetitionFullResponse(
    val awards: List<AwardProject> = emptyList(),
    val creditsSummary: CreditsSummary? = null,
)

// ==================== Labor Club Models ====================
@Serializable
data class LaborClubProgressInfo(
    @SerialName("SumScore") val sumScore: Double = 0.0,
    @SerialName("Progress") val progress: Double = 0.0,
) {
    val isCompleted get() = progress >= 100
    val finishCount get() = (progress / 10).toInt()
}

@Serializable
data class LaborClubActivity(
    @SerialName("ID") val id: String = "",
    @SerialName("Title") val title: String = "",
    @SerialName("State") val state: Int = 0,
    @SerialName("StateName") val stateName: String = "",
    @SerialName("TypeID") val typeId: String = "",
    @SerialName("TypeName") val typeName: String = "",
    @SerialName("StartTime") val startTime: String = "",
    @SerialName("EndTime") val endTime: String = "",
    @SerialName("ClubID") val clubId: String = "",
    @SerialName("ClubName") val clubName: String = "",
    @SerialName("MemberNum") val memberNum: Int = 0,
    @SerialName("PeopleNum") val peopleNum: Int = 0,
    @SerialName("ChargeUserNo") val chargeUserNo: String = "",
    @SerialName("ChargeUserName") val chargeUserName: String = "",
    @SerialName("SignUpStartTime") val signUpStartTime: String = "",
    @SerialName("SignUpEndTime") val signUpEndTime: String = "",
    @SerialName("AddTime") val addTime: String = "",
) {
    /** 运行时附加的签到列表 */
    @kotlinx.serialization.Transient
    var signList: List<SignItem>? = null

    val isAllSigned: Boolean get() {
        val list = signList ?: return true
        return list.isEmpty() || list.all { it.isSign }
    }

    val signInStatus: String get() {
        val list = signList
        if (list == null || list.isEmpty()) return "默认签到"
        val signed = list.count { it.isSign }
        if (list.size == 1) {
            val s = list.first()
            return if (s.isSign) "😋 已签到"
            else try {
                val end = java.time.LocalDateTime.parse(s.endTime.replace(" ", "T"))
                if (java.time.LocalDateTime.now().isAfter(end)) "😭 未签到" else "🤔 待签到"
            } catch (_: Exception) { "🤔 待签到" }
        }
        return when {
            signed == list.size -> "已完成签到 ($signed/${list.size})"
            signed > 0 -> "部分签到 ($signed/${list.size})"
            else -> "未签到 (0/${list.size})"
        }
    }
}

@Serializable
data class LaborClubInfo(
    @SerialName("ID") val id: String = "",
    @SerialName("Name") val name: String = "",
    @SerialName("TypeName") val typeName: String? = null,
    @SerialName("Ico") val ico: String? = null,
    @SerialName("CairmanName") val chairmanName: String? = null,
    @SerialName("MemberNum") val memberNum: Int = 0,
)

@Serializable
data class SignItem(
    @SerialName("ID") val id: String = "",
    @SerialName("Type") val type: Int = 0,
    @SerialName("TypeName") val typeName: String = "",
    @SerialName("StartTime") val startTime: String = "",
    @SerialName("EndTime") val endTime: String = "",
    @SerialName("IsSign") val isSign: Boolean = false,
    @SerialName("SignTime") val signTime: String? = null,
) {
    val statusText get() = if (isSign) "已签到" else "未签到"
}

@Serializable
data class SignInResponse(
    val code: Int = 0,
    val msg: String = "",
) {
    val isSuccess get() = code == 0
}

@Serializable
data class ActivityFormField(
    @SerialName("ID") val id: String = "",
    @SerialName("Name") val name: String = "",
    @SerialName("Value") val value: String = "",
    @SerialName("IsMust") val isMust: Boolean = false,
    @SerialName("FieldType") val fieldType: Int = 1,
)

@Serializable
data class ActivityTeacher(
    @SerialName("UserName") val userName: String = "",
    @SerialName("UserNo") val userNo: String = "",
)

data class ActivityDetail(
    val id: String = "",
    val title: String = "",
    val startTime: String = "",
    val endTime: String = "",
    val chargeUserName: String = "",
    val clubName: String = "",
    val memberNum: Int = 0,
    val peopleNum: Int = 0,
    val signUpStartTime: String = "",
    val signUpEndTime: String = "",
    val formData: List<ActivityFormField> = emptyList(),
    val teacherList: List<ActivityTeacher> = emptyList(),
    val signList: List<SignItem> = emptyList(),
) {
    val location: String get() = formData.firstOrNull {
        it.name in listOf("活动地址", "Location", "地点", "活动地点")
    }?.value ?: ""

    val teacherNames: String get() = teacherList.joinToString("、") { it.userName }
}

// ==================== Course Schedule Models ====================
@Serializable
data class CourseScheduleRecord(
    val kch: String? = null,       // 课程号
    val kxh: String? = null,       // 课序号
    val kcm: String? = null,       // 课程名
    val xf: Int? = null,           // 学分
    val xs: Int? = null,           // 学时
    val kkxsjc: String? = null,    // 开课院系简称
    val kslxmc: String? = null,    // 考试类型名称
    val skjs: String? = null,      // 授课教师
    val bkskrl: Int? = null,       // 本科生课容量
    val bkskyl: Int? = null,       // 本科生课余量
    val xkmssm: String? = null,    // 选课模式说明
    val kkxqm: String? = null,     // 开课校区名
    val skzc: String? = null,      // 上课周次
    val skxq: Int? = null,         // 上课星期
    val skjc: Int? = null,         // 上课节次
    val cxjc: Int? = null,         // 持续节次
    val zcsm: String? = null,      // 周次说明
    val kclbmc: String? = null,    // 课程类别名称
    val xqm: String? = null,      // 校区名
    val jxlm: String? = null,     // 教学楼名
    val jasm: String? = null,     // 教室名
    val mxbj: String? = null,     // 面向班级
    val xss: Int? = null,         // 学生数
) {
    val classTimeStr: String?
        get() = if (skjc != null && cxjc != null) "$skjc-${skjc!! + cxjc!! - 1}" else null

    val weekdayStr: String?
        get() {
            val weekdays = arrayOf("", "周一", "周二", "周三", "周四", "周五", "周六", "周日")
            return if (skxq != null && skxq in 1..7) weekdays[skxq!!] else null
        }

    val scheduleDescription: String
        get() {
            val parts = mutableListOf<String>()
            weekdayStr?.let { parts.add(it) }
            classTimeStr?.let { parts.add("第${it}节") }
            zcsm?.takeIf { it.isNotEmpty() }?.let { parts.add(it) }
            if (jxlm != null && jasm != null) parts.add("$jxlm$jasm")
            else xqm?.let { parts.add(it) }
            return parts.joinToString(" ")
        }
}

// ==================== Student Schedule Models ====================
@Serializable
data class ScheduleTimePlace(
    val classWeek: String = "",
    val classDay: Int = 0,
    val classSessions: Int = 0,
    val continuingSession: Int = 0,
    val campusName: String = "",
    val teachingBuildingName: String = "",
    val classroomName: String = "",
    val weekDescription: String = "",
    val coursePropertiesName: String = "",
    val coureName: String = "",
) {
    val endSession get() = classSessions + continuingSession - 1
    val locationDescription get() = "$campusName $teachingBuildingName $classroomName".trim()
}

@Serializable
data class ScheduleCourseId(
    val executiveEducationPlanNumber: String = "",
    val coureNumber: String = "",
    val coureSequenceNumber: String = "",
    val studentNumber: String = "",
)

@Serializable
data class ScheduleCourse(
    val id: ScheduleCourseId = ScheduleCourseId(),
    val programPlanNumber: String = "",
    val courseName: String = "",
    val unit: Double = 0.0,
    val programPlanName: String = "",
    val attendClassTeacher: String = "",
    val studyModeName: String = "",
    val coursePropertiesName: String = "",
    val examTypeName: String = "",
    val courseCategoryName: String? = null,
    val restrictedCondition: String? = null,
    val timeAndPlaceList: List<ScheduleTimePlace> = emptyList(),
    val selectCourseStatusName: String = "",
) {
    val courseCode get() = id.coureNumber
    val courseSequence get() = id.coureSequenceNumber
    val uniqueKey get() = "${id.coureNumber}_${id.coureSequenceNumber}"
}

@Serializable
data class ScheduleDateInfo(
    val programPlanCode: String = "",
    val programPlanName: String = "",
    val totalUnits: Double = 0.0,
    val selectCourseList: List<ScheduleCourse> = emptyList(),
)

@Serializable
data class StudentScheduleResponse(
    val allUnits: Double = 0.0,
    val errorMessage: String = "",
    val showSite: Boolean = true,
    val dateList: List<ScheduleDateInfo> = emptyList(),
) {
    val courses: List<ScheduleCourse>
        get() = dateList.flatMap { it.selectCourseList }
}

// ==================== Plan Completion Models ====================
data class PlanCourse(
    val courseCode: String = "",
    val courseName: String = "",
    val credits: Double? = null,
    val score: String? = null,
    val examDate: String? = null,
    val courseType: String = "",
    val isPassed: Boolean = false,
    val statusDescription: String = "未修读",
)

data class PlanCategory(
    val categoryId: String = "",
    val categoryName: String = "",
    val minCredits: Double = 0.0,
    val completedCredits: Double = 0.0,
    val totalCourses: Int = 0,
    val passedCourses: Int = 0,
    val failedCourses: Int = 0,
    val missingRequiredCourses: Int = 0,
    val subcategories: List<PlanCategory> = emptyList(),
    val courses: List<PlanCourse> = emptyList(),
) {
    val completionPercentage: Double
        get() = if (minCredits <= 0) 0.0 else (completedCredits / minCredits * 100).coerceIn(0.0, 100.0)
    val isCompleted get() = completedCredits >= minCredits
}

data class PlanCompletionInfo(
    val planName: String = "",
    val major: String = "",
    val grade: String = "",
    val categories: List<PlanCategory> = emptyList(),
    val totalCategories: Int = 0,
    val totalCourses: Int = 0,
    val passedCourses: Int = 0,
    val failedCourses: Int = 0,
    val unreadCourses: Int = 0,
    val missingRequiredCourses: Int = 0,
    val estimatedGraduationCredits: Double = 0.0,
)

data class PlanOption(
    val planId: String,
    val planName: String,
    val planType: String = "主修",
    val isCurrent: Boolean = false,
)

data class PlanSelectionResponse(
    val options: List<PlanOption> = emptyList(),
    val hint: String? = null,
)

// ==================== User Credentials ====================
data class UserCredentials(
    val userId: String,
    val ecPassword: String,
    val password: String,
)

// ==================== YKT Electricity Payment Models ====================

/** 选项项（校区/楼栋/楼层/房间） */
data class SelectOption(val value: String, val name: String) {
    companion object {
        fun parseList(response: String): List<SelectOption> {
            if (response.isBlank()) return emptyList()
            return response.split("|").mapNotNull { item ->
                val parts = item.trim().split(",", limit = 2)
                if (parts.size >= 2) SelectOption(parts[0].trim(), parts[1].trim()) else null
            }
        }
    }
}

/** 学生信息（电费充值页面） */
data class StudentInfo(
    val studentId: String = "",
    val name: String = "",
    val accountStatus: String = "",
    val cardStatus: String = "",
    val balance: Double = 0.0,
    val accId: String = "",
) {
    companion object {
        fun fromHtml(html: String): StudentInfo {
            fun extract(pattern: String) = Regex(pattern, RegexOption.IGNORE_CASE).find(html)?.groupValues?.getOrNull(1)?.trim() ?: ""
            val balance = Regex("校园余额</label>\\s*<label>([\\d.]+)</label>", RegexOption.IGNORE_CASE).find(html)?.groupValues?.get(1)?.toDoubleOrNull() ?: 0.0
            val accId = Regex("name=\"accId\"\\s+value\\s*=\\s*\"(\\d+)\"").find(html)?.groupValues?.get(1) ?: ""
            return StudentInfo(
                studentId = extract("编号</label>\\s*<label>(\\d+)</label>"),
                name = extract("姓名</label>\\s*<label>([^<]+)</label>"),
                accountStatus = extract("账户状态</label>\\s*<label>([^<]+)</label>"),
                cardStatus = extract("卡状态</label>\\s*<label>([^<]+)</label>"),
                balance = balance,
                accId = accId,
            )
        }
    }
}

/** 电费充值请求 */
data class UtilityPaymentRequest(
    val roomId: String,
    val dormId: String,
    val dormName: String,
    val buildName: String,
    val floorName: String,
    val roomName: String,
    val accId: String,
    val balances: String,
    val payType: String = "2",
    val choosePayType: String = "1",
    val money: Int,
) {
    fun toFormData() = mapOf(
        "roomId" to roomId, "dormId" to dormId, "dormName" to dormName,
        "buildName" to buildName, "floorName" to floorName, "roomName" to roomName,
        "accId" to accId, "balances" to balances, "payType" to payType,
        "choosePayType" to choosePayType, "money" to money.toString(),
    )
}

/** 电费充值结果 */
data class UtilityPaymentResult(val success: Boolean, val message: String) {
    companion object {
        fun fromHtml(html: String): UtilityPaymentResult {
            val msg = Regex("id=\"message\"[^>]*value\\s*=\\s*\"([^\"]*)\"").find(html)?.groupValues?.get(1) ?: ""
            if (msg.contains("成功")) return UtilityPaymentResult(true, msg)
            if (msg.isNotEmpty()) return UtilityPaymentResult(false, msg)
            if (html.contains("缴费成功") || html.contains("充值成功")) return UtilityPaymentResult(true, "充值成功")
            return UtilityPaymentResult(false, "未知结果")
        }
    }
}

/** 购电记录 */
data class ElectricPurchaseRecord(
    val name: String = "",
    val studentId: String = "",
    val area: String = "",
    val roomInfo: String = "",
    val amount: Double = 0.0,
    val purchaseDate: String = "",
    val department: String = "",
)

/** 购电记录查询结果 */
data class ElectricPurchaseQueryResult(
    val startDate: String,
    val endDate: String,
    val records: List<ElectricPurchaseRecord> = emptyList(),
) {
    val totalAmount get() = records.sumOf { it.amount }

    companion object {
        fun fromHtml(html: String, startDate: String, endDate: String): ElectricPurchaseQueryResult {
            val records = mutableListOf<ElectricPurchaseRecord>()
            val rowRegex = Regex("<tr>\\s*<td>([^<]*)</td>\\s*<td>([^<]*)</td>\\s*<td>([^<]*)</td>\\s*<td[^>]*>([^<]*)</td>\\s*<td>([^<]*)</td>\\s*<td[^>]*>([^<]*)</td>\\s*<td>([^<]*)</td>\\s*</tr>", setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL))
            for (match in rowRegex.findAll(html)) {
                val g = match.groupValues.drop(1).map { it.trim() }
                if (g[0] == "姓名" || g[0].isEmpty()) continue
                records.add(ElectricPurchaseRecord(g[0], g[1], g[2], g[3], g[4].toDoubleOrNull() ?: 0.0, g[5], g[6]))
            }
            return ElectricPurchaseQueryResult(startDate, endDate, records)
        }
    }
}
