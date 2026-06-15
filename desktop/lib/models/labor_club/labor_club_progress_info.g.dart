// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'labor_club_progress_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LaborClubProgressInfo _$LaborClubProgressInfoFromJson(
  Map<String, dynamic> json,
) => LaborClubProgressInfo(
  sumScore: (json['SumScore'] as num).toDouble(),
  progress: json['Progress'] as num,
);

Map<String, dynamic> _$LaborClubProgressInfoToJson(
  LaborClubProgressInfo instance,
) => <String, dynamic>{
  'SumScore': instance.sumScore,
  'Progress': instance.progress,
};
