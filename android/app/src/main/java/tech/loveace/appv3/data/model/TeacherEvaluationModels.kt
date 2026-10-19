package tech.loveace.appv3.data.model

/**
 * 评教首页“首次访问须知/倒计时”保护状态。
 * 仅解析脱敏的结构字段（隐藏 input 与 JS 状态变量），不含任何个人数据。
 */
data class TeacherEvaluationIndexProtection(
    val schoolId: String = "",
    val infoOff: String = "",
    val infoTimeSeconds: Int = 0,
    val isFinished: String = "",
    val isFinishedResolved: Boolean = false,
    val isFirstVisit: String = "",
    val isFirstVisitResolved: Boolean = false,
    val hasAhcjTimer: Boolean = false,
) {
    /**
     * 命中条件：infoOff=1 且存在倒计时且未见“已完成/已访问”的明确证据。
     * 状态变量解析失败时保守走等待，避免过早 search/提交。
     */
    val requiresInitialWait: Boolean
        get() {
            if (infoOff != "1" || infoTimeSeconds <= 0 || !hasAhcjTimer) return false
            val finishedKnown = isFinishedResolved && isFinished != "unfinished"
            val visitedKnown = isFirstVisitResolved && isFirstVisit != "unVisit"
            return !(finishedKnown || visitedKnown)
        }

    /** 保护等待秒数：倒计时 + 安全余量 */
    val waitSeconds: Int
        get() = if (infoTimeSeconds > 0) infoTimeSeconds + SAFETY_SECONDS else 0

    companion object {
        private const val SAFETY_SECONDS = 5

        val NONE = TeacherEvaluationIndexProtection()
    }
}

data class TeacherEvaluationIndex(
    val tokenValue: String,
    val isClosed: Boolean,
    val closedMessage: String = "",
    val protection: TeacherEvaluationIndexProtection = TeacherEvaluationIndexProtection.NONE,
)

data class TeacherEvaluationCourseList(
    val tokenValue: String,
    val isClosed: Boolean,
    val closedMessage: String = "",
    val courses: List<TeacherEvaluationCourse> = emptyList(),
    val protection: TeacherEvaluationIndexProtection = TeacherEvaluationIndexProtection.NONE,
)

data class TeacherEvaluationCourse(
    val name: String = "",
    val teacher: String = "",
    val evaluatedPeople: String = "",
    val evaluatedPeopleNumber: String = "",
    val coureSequenceNumber: String = "",
    val evaluationContentNumber: String = "",
    val questionnaireCode: String = "",
    val questionnaireName: String = "",
    val isEvaluated: Boolean = false,
) {
    val stableId: String?
        get() {
            val parts = listOf(
                evaluatedPeopleNumber,
                coureSequenceNumber,
                evaluationContentNumber,
                questionnaireCode,
            )
            return if (parts.all { it.isNotBlank() }) parts.joinToString("_") else null
        }

    val displayId: String
        get() = stableId ?: listOf(
            evaluatedPeopleNumber,
            evaluationContentNumber,
            questionnaireCode,
            name,
            teacher,
        ).filter { it.isNotBlank() }.joinToString("_").ifBlank { hashCode().toString() }

    fun matches(other: TeacherEvaluationCourse): Boolean {
        val leftStableId = stableId
        val rightStableId = other.stableId
        if (!leftStableId.isNullOrBlank() && !rightStableId.isNullOrBlank()) {
            return leftStableId == rightStableId
        }
        return evaluatedPeopleNumber.isNotBlank() &&
            evaluatedPeopleNumber == other.evaluatedPeopleNumber &&
            evaluationContentNumber.isNotBlank() &&
            evaluationContentNumber == other.evaluationContentNumber
    }
}

data class TeacherEvaluationQuestionnaire(
    val title: String = "",
    val tokenValue: String = "",
    val questionnaireCode: String = "",
    val evaluatedPeopleNumber: String = "",
    val evaluationContent: String = "",
    val evaluatedPerson: String = "",
    val radioQuestions: List<TeacherEvaluationRadioQuestion> = emptyList(),
    val textQuestions: List<TeacherEvaluationTextQuestion> = emptyList(),
)

data class TeacherEvaluationRadioQuestion(
    val key: String,
    val category: String = "",
    val title: String = "",
    val options: List<TeacherEvaluationOption> = emptyList(),
)

data class TeacherEvaluationOption(
    val key: String,
    val value: String,
    val score: Double = 0.0,
    val weight: Double = 0.0,
    val label: String = "",
)

data class TeacherEvaluationTextQuestion(
    val key: String,
    val title: String = "",
    val required: Boolean = false,
    val type: TeacherEvaluationTextType = TeacherEvaluationTextType.General,
)

enum class TeacherEvaluationTextType { Overall, Inspiration, Suggestion, General }

data class TeacherEvaluationPreparedForm(
    val course: TeacherEvaluationCourse,
    val questionnaireTitle: String = "",
    val formData: Map<String, String>,
)

data class TeacherEvaluationSubmitResult(
    val success: Boolean,
    val message: String,
)
