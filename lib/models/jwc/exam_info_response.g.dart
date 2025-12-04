// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'exam_info_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ExamInfoResponse _$ExamInfoResponseFromJson(Map<String, dynamic> json) =>
    ExamInfoResponse(
      exams: (json['exams'] as List<dynamic>)
          .map((e) => UnifiedExamInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
      totalCount: (json['total_count'] as num).toInt(),
    );

Map<String, dynamic> _$ExamInfoResponseToJson(ExamInfoResponse instance) =>
    <String, dynamic>{
      'exams': instance.exams,
      'total_count': instance.totalCount,
    };
