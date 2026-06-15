// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'exam_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UnifiedExamInfo _$UnifiedExamInfoFromJson(Map<String, dynamic> json) =>
    UnifiedExamInfo(
      courseName: json['course_name'] as String,
      examDate: json['exam_date'] as String,
      examTime: json['exam_time'] as String,
      examLocation: json['exam_location'] as String,
      examType: json['exam_type'] as String,
      note: json['note'] as String,
    );

Map<String, dynamic> _$UnifiedExamInfoToJson(UnifiedExamInfo instance) =>
    <String, dynamic>{
      'course_name': instance.courseName,
      'exam_date': instance.examDate,
      'exam_time': instance.examTime,
      'exam_location': instance.examLocation,
      'exam_type': instance.examType,
      'note': instance.note,
    };
