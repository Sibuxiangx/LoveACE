// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'academic_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AcademicInfo _$AcademicInfoFromJson(Map<String, dynamic> json) => AcademicInfo(
  completedCourses: (json['courseNum'] as num).toInt(),
  failedCourses: (json['coursePas'] as num).toInt(),
  gpa: (json['gpa'] as num).toDouble(),
  pendingCourses: (json['courseNum_bxqyxd'] as num).toInt(),
  currentTerm: json['zxjxjhh'] as String,
);

Map<String, dynamic> _$AcademicInfoToJson(AcademicInfo instance) =>
    <String, dynamic>{
      'courseNum': instance.completedCourses,
      'coursePas': instance.failedCourses,
      'gpa': instance.gpa,
      'courseNum_bxqyxd': instance.pendingCourses,
      'zxjxjhh': instance.currentTerm,
    };
