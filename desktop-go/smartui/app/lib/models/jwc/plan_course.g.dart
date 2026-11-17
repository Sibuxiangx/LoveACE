// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'plan_course.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PlanCourse _$PlanCourseFromJson(Map<String, dynamic> json) => PlanCourse(
  courseCode: json['course_code'] as String,
  courseName: json['course_name'] as String,
  credits: (json['credits'] as num?)?.toDouble(),
  score: json['score'] as String?,
  examDate: json['exam_date'] as String?,
  courseType: json['course_type'] as String? ?? '',
  isPassed: json['is_passed'] as bool? ?? false,
  statusDescription: json['status_description'] as String? ?? '未修读',
);

Map<String, dynamic> _$PlanCourseToJson(PlanCourse instance) =>
    <String, dynamic>{
      'course_code': instance.courseCode,
      'course_name': instance.courseName,
      'credits': instance.credits,
      'score': instance.score,
      'exam_date': instance.examDate,
      'course_type': instance.courseType,
      'is_passed': instance.isPassed,
      'status_description': instance.statusDescription,
    };
