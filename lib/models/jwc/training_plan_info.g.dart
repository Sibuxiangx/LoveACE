// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'training_plan_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TrainingPlanInfo _$TrainingPlanInfoFromJson(Map<String, dynamic> json) =>
    TrainingPlanInfo(
      planName: json['planName'] as String,
      majorName: json['majorName'] as String,
      grade: json['grade'] as String,
    );

Map<String, dynamic> _$TrainingPlanInfoToJson(TrainingPlanInfo instance) =>
    <String, dynamic>{
      'planName': instance.planName,
      'majorName': instance.majorName,
      'grade': instance.grade,
    };
