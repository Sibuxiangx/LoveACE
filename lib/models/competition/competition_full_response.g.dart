// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'competition_full_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CompetitionFullResponse _$CompetitionFullResponseFromJson(
  Map<String, dynamic> json,
) => CompetitionFullResponse(
  studentId: json['student_id'] as String,
  totalAwardsCount: (json['total_awards_count'] as num?)?.toInt() ?? 0,
  awards:
      (json['awards'] as List<dynamic>?)
          ?.map((e) => AwardProject.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
  creditsSummary: json['credits_summary'] == null
      ? null
      : CreditsSummary.fromJson(
          json['credits_summary'] as Map<String, dynamic>,
        ),
);

Map<String, dynamic> _$CompetitionFullResponseToJson(
  CompetitionFullResponse instance,
) => <String, dynamic>{
  'student_id': instance.studentId,
  'total_awards_count': instance.totalAwardsCount,
  'awards': instance.awards,
  'credits_summary': instance.creditsSummary,
};
