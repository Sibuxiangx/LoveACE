// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'electricity_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ElectricityInfo _$ElectricityInfoFromJson(
  Map<String, dynamic> json,
) => ElectricityInfo(
  balance: ElectricityBalance.fromJson(json['balance'] as Map<String, dynamic>),
  usageRecords: (json['usage_records'] as List<dynamic>)
      .map((e) => ElectricityUsageRecord.fromJson(e as Map<String, dynamic>))
      .toList(),
  payments: (json['payments'] as List<dynamic>)
      .map((e) => PaymentRecord.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$ElectricityInfoToJson(ElectricityInfo instance) =>
    <String, dynamic>{
      'balance': instance.balance,
      'usage_records': instance.usageRecords,
      'payments': instance.payments,
    };
