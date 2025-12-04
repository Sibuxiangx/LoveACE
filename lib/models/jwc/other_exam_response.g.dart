// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'other_exam_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

OtherExamResponse _$OtherExamResponseFromJson(Map<String, dynamic> json) =>
    OtherExamResponse(
      pageSize: (json['pageSize'] as num).toInt(),
      pageNum: (json['pageNum'] as num).toInt(),
      pageContext: Map<String, int>.from(json['pageContext'] as Map),
      records: (json['records'] as List<dynamic>?)
          ?.map((e) => OtherExamRecord.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$OtherExamResponseToJson(OtherExamResponse instance) =>
    <String, dynamic>{
      'pageSize': instance.pageSize,
      'pageNum': instance.pageNum,
      'pageContext': instance.pageContext,
      'records': instance.records,
    };
