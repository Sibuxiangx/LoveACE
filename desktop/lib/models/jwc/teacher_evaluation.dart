class TeacherEvaluationIndex {
  final String tokenValue;
  final bool isClosed;
  final String closedMessage;

  const TeacherEvaluationIndex({
    required this.tokenValue,
    required this.isClosed,
    this.closedMessage = '',
  });
}

class TeacherEvaluationCourseList {
  final String tokenValue;
  final bool isClosed;
  final String closedMessage;
  final List<TeacherEvaluationCourse> courses;

  const TeacherEvaluationCourseList({
    required this.tokenValue,
    required this.isClosed,
    this.closedMessage = '',
    this.courses = const [],
  });
}

class TeacherEvaluationCourse {
  final String name;
  final String teacher;
  final String evaluatedPeople;
  final String evaluatedPeopleNumber;
  final String coureSequenceNumber;
  final String evaluationContentNumber;
  final String questionnaireCode;
  final String questionnaireName;
  final bool isEvaluated;

  const TeacherEvaluationCourse({
    this.name = '',
    this.teacher = '',
    this.evaluatedPeople = '',
    this.evaluatedPeopleNumber = '',
    this.coureSequenceNumber = '',
    this.evaluationContentNumber = '',
    this.questionnaireCode = '',
    this.questionnaireName = '',
    this.isEvaluated = false,
  });

  String? get stableId {
    final parts = [
      evaluatedPeopleNumber,
      coureSequenceNumber,
      evaluationContentNumber,
      questionnaireCode,
    ];
    return parts.every((part) => part.isNotEmpty) ? parts.join('_') : null;
  }

  String get displayId {
    return stableId ??
        [
          evaluatedPeopleNumber,
          evaluationContentNumber,
          questionnaireCode,
          name,
          teacher,
        ].where((part) => part.isNotEmpty).join('_').ifEmpty(hashCode.toString());
  }

  String get displayName {
    return [name, teacher].where((part) => part.isNotEmpty).join(' / ').ifEmpty(displayId);
  }

  bool matches(TeacherEvaluationCourse other) {
    final leftStableId = stableId;
    final rightStableId = other.stableId;
    if (leftStableId != null && rightStableId != null) {
      return leftStableId == rightStableId;
    }
    return evaluatedPeopleNumber.isNotEmpty &&
        evaluatedPeopleNumber == other.evaluatedPeopleNumber &&
        evaluationContentNumber.isNotEmpty &&
        evaluationContentNumber == other.evaluationContentNumber;
  }
}

class TeacherEvaluationQuestionnaire {
  final String title;
  final String tokenValue;
  final String questionnaireCode;
  final String evaluatedPeopleNumber;
  final String evaluationContent;
  final String evaluatedPerson;
  final List<TeacherEvaluationRadioQuestion> radioQuestions;
  final List<TeacherEvaluationTextQuestion> textQuestions;

  const TeacherEvaluationQuestionnaire({
    this.title = '',
    this.tokenValue = '',
    this.questionnaireCode = '',
    this.evaluatedPeopleNumber = '',
    this.evaluationContent = '',
    this.evaluatedPerson = '',
    this.radioQuestions = const [],
    this.textQuestions = const [],
  });
}

class TeacherEvaluationRadioQuestion {
  final String key;
  final String category;
  final String title;
  final List<TeacherEvaluationOption> options;

  const TeacherEvaluationRadioQuestion({
    required this.key,
    this.category = '',
    this.title = '',
    this.options = const [],
  });
}

class TeacherEvaluationOption {
  final String key;
  final String value;
  final double score;
  final double weight;
  final String label;

  const TeacherEvaluationOption({
    required this.key,
    required this.value,
    this.score = 0,
    this.weight = 0,
    this.label = '',
  });
}

class TeacherEvaluationTextQuestion {
  final String key;
  final String title;
  final bool required;
  final TeacherEvaluationTextType type;

  const TeacherEvaluationTextQuestion({
    required this.key,
    this.title = '',
    this.required = false,
    this.type = TeacherEvaluationTextType.general,
  });
}

enum TeacherEvaluationTextType { overall, inspiration, suggestion, general }

class TeacherEvaluationPreparedForm {
  final TeacherEvaluationCourse course;
  final String questionnaireTitle;
  final Map<String, String> formData;

  const TeacherEvaluationPreparedForm({
    required this.course,
    this.questionnaireTitle = '',
    required this.formData,
  });
}

class TeacherEvaluationSubmitResult {
  final bool success;
  final String message;

  const TeacherEvaluationSubmitResult({
    required this.success,
    required this.message,
  });
}

extension _NonEmptyString on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
