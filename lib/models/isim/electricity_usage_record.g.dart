// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'electricity_usage_record.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ElectricityUsageRecord _$ElectricityUsageRecordFromJson(
  Map<String, dynamic> json,
) => ElectricityUsageRecord(
  recordTime: json['record_time'] as String,
  usageAmount: (json['usage_amount'] as num).toDouble(),
  meterName: json['meter_name'] as String,
);

Map<String, dynamic> _$ElectricityUsageRecordToJson(
  ElectricityUsageRecord instance,
) => <String, dynamic>{
  'record_time': instance.recordTime,
  'usage_amount': instance.usageAmount,
  'meter_name': instance.meterName,
};
