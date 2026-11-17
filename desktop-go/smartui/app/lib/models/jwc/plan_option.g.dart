// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'plan_option.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PlanOption _$PlanOptionFromJson(Map<String, dynamic> json) => PlanOption(
  planId: json['plan_id'] as String,
  planName: json['plan_name'] as String,
  planType: json['plan_type'] as String,
  isCurrent: json['is_current'] as bool? ?? false,
);

Map<String, dynamic> _$PlanOptionToJson(PlanOption instance) =>
    <String, dynamic>{
      'plan_id': instance.planId,
      'plan_name': instance.planName,
      'plan_type': instance.planType,
      'is_current': instance.isCurrent,
    };

PlanSelectionResponse _$PlanSelectionResponseFromJson(
  Map<String, dynamic> json,
) => PlanSelectionResponse(
  options: (json['options'] as List<dynamic>)
      .map((e) => PlanOption.fromJson(e as Map<String, dynamic>))
      .toList(),
  hint: json['hint'] as String?,
);

Map<String, dynamic> _$PlanSelectionResponseToJson(
  PlanSelectionResponse instance,
) => <String, dynamic>{'options': instance.options, 'hint': instance.hint};
