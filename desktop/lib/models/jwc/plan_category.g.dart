// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'plan_category.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PlanCategory _$PlanCategoryFromJson(Map<String, dynamic> json) => PlanCategory(
  categoryId: json['category_id'] as String,
  categoryName: json['category_name'] as String,
  minCredits: (json['min_credits'] as num?)?.toDouble() ?? 0.0,
  completedCredits: (json['completed_credits'] as num?)?.toDouble() ?? 0.0,
  totalCourses: (json['total_courses'] as num?)?.toInt() ?? 0,
  passedCourses: (json['passed_courses'] as num?)?.toInt() ?? 0,
  failedCourses: (json['failed_courses'] as num?)?.toInt() ?? 0,
  missingRequiredCourses:
      (json['missing_required_courses'] as num?)?.toInt() ?? 0,
  subcategories:
      (json['subcategories'] as List<dynamic>?)
          ?.map((e) => PlanCategory.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
  courses:
      (json['courses'] as List<dynamic>?)
          ?.map((e) => PlanCourse.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
);

Map<String, dynamic> _$PlanCategoryToJson(PlanCategory instance) =>
    <String, dynamic>{
      'category_id': instance.categoryId,
      'category_name': instance.categoryName,
      'min_credits': instance.minCredits,
      'completed_credits': instance.completedCredits,
      'total_courses': instance.totalCourses,
      'passed_courses': instance.passedCourses,
      'failed_courses': instance.failedCourses,
      'missing_required_courses': instance.missingRequiredCourses,
      'subcategories': instance.subcategories,
      'courses': instance.courses,
    };
