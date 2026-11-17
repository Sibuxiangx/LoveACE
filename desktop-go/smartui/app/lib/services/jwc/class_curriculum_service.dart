import '../../bridge/mygo_bridge.dart';
import '../../models/backend/uni_response.dart';
import '../../models/jwc/course_schedule_record.dart';
import '../../models/jwc/term_item.dart';

class ClassCurriculumOption {
  final String code;
  final String name;

  ClassCurriculumOption({required this.code, required this.name});

  factory ClassCurriculumOption.fromJson(Map<String, dynamic> json) {
    return ClassCurriculumOption(
      code: json['code'] as String,
      name: json['name'] as String,
    );
  }
}

class ClassCurriculumClassOption {
  final String planCode;
  final String classCode;
  final String className;
  final String? departmentName;
  final String? subjectName;

  ClassCurriculumClassOption({
    required this.planCode,
    required this.classCode,
    required this.className,
    this.departmentName,
    this.subjectName,
  });

  factory ClassCurriculumClassOption.fromJson(Map<String, dynamic> json) {
    return ClassCurriculumClassOption(
      planCode: json['plan_code'] as String,
      classCode: json['class_code'] as String,
      className: json['class_name'] as String,
      departmentName: json['department_name'] as String?,
      subjectName: json['subject_name'] as String?,
    );
  }
}

/// The class curriculum the school publishes, read through the Go side.
class ClassCurriculumService {
  Future<UniResponse<List<TermItem>>> getTerms() {
    return readGo(
      'SmartData.ClassTerms',
      (json) => jsonList(json).map(TermItem.fromJson).toList(),
    );
  }

  Future<UniResponse<List<ClassCurriculumOption>>> getDepartments() {
    return readGo(
      'SmartData.Departments',
      (json) => jsonList(json).map(ClassCurriculumOption.fromJson).toList(),
    );
  }

  Future<UniResponse<List<ClassCurriculumOption>>> getSubjects({
    required String departmentCode,
  }) {
    return readGo(
      'SmartData.Subjects',
      (json) => jsonList(json).map(ClassCurriculumOption.fromJson).toList(),
      [departmentCode],
    );
  }

  Future<UniResponse<List<ClassCurriculumClassOption>>> queryClasses({
    required String planCode,
    required String departmentCode,
    String? subjectCode,
  }) {
    return readGo(
      'SmartData.Classes',
      (json) => jsonList(json).map(ClassCurriculumClassOption.fromJson).toList(),
      [planCode, departmentCode, subjectCode],
    );
  }

  Future<UniResponse<List<CourseScheduleRecord>>> queryClassCurriculum({
    required String planCode,
    required String classCode,
  }) {
    return readGo(
      'SmartData.ClassCurriculum',
      (json) => jsonList(json).map(CourseScheduleRecord.fromJson).toList(),
      [planCode, classCode],
    );
  }
}
