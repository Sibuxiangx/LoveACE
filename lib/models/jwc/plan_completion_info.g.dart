// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'plan_completion_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PlanCompletionInfo _$PlanCompletionInfoFromJson(Map<String, dynamic> json) =>
    PlanCompletionInfo(
      planName: json['plan_name'] as String,
      major: json['major'] as String,
      grade: json['grade'] as String,
      categories: (json['categories'] as List<dynamic>)
          .map((e) => PlanCategory.fromJson(e as Map<String, dynamic>))
          .toList(),
      totalCategories: (json['total_categories'] as num?)?.toInt() ?? 0,
      totalCourses: (json['total_courses'] as num?)?.toInt() ?? 0,
      passedCourses: (json['passed_courses'] as num?)?.toInt() ?? 0,
      failedCourses: (json['failed_courses'] as num?)?.toInt() ?? 0,
      unreadCourses: (json['unread_courses'] as num?)?.toInt() ?? 0,
      estimatedGraduationCredits:
          (json['estimated_graduation_credits'] as num?)?.toDouble() ?? 0.0,
    );

Map<String, dynamic> _$PlanCompletionInfoToJson(PlanCompletionInfo instance) =>
    <String, dynamic>{
      'plan_name': instance.planName,
      'major': instance.major,
      'grade': instance.grade,
      'categories': instance.categories,
      'total_categories': instance.totalCategories,
      'total_courses': instance.totalCourses,
      'passed_courses': instance.passedCourses,
      'failed_courses': instance.failedCourses,
      'unread_courses': instance.unreadCourses,
      'estimated_graduation_credits': instance.estimatedGraduationCredits,
    };
