package tech.loveace.appv3.data.model

data class TeacherEvaluationIndex(
    val tokenValue: String,
    val isClosed: Boolean,
    val closedMessage: String = "",
)

data class TeacherEvaluationCourseList(
    val tokenValue: String,
    val isClosed: Boolean,
    val closedMessage: String = "",
    val courses: List<TeacherEvaluationCourse> = emptyList(),
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
