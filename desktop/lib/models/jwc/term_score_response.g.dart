// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'term_score_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TermScoreResponse _$TermScoreResponseFromJson(Map<String, dynamic> json) =>
    TermScoreResponse(
      totalCount: (json['total_count'] as num).toInt(),
      records: (json['records'] as List<dynamic>)
          .map((e) => ScoreRecord.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$TermScoreResponseToJson(TermScoreResponse instance) =>
    <String, dynamic>{
      'total_count': instance.totalCount,
      'records': instance.records,
    };
