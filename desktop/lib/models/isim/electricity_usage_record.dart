import 'package:json_annotation/json_annotation.dart';

part 'electricity_usage_record.g.dart';

/// 用电记录模型
///
/// 包含记录时间、用电量和电表名称
@JsonSerializable()
class ElectricityUsageRecord {
  /// 记录时间 "YYYY-MM-DD HH:MM:SS"
  @JsonKey(name: 'record_time')
  final String recordTime;

  /// 用电量（度）
  @JsonKey(name: 'usage_amount')
  final double usageAmount;

  /// 电表名称（区分普通/空调）
  @JsonKey(name: 'meter_name')
  final String meterName;

  ElectricityUsageRecord({
    required this.recordTime,
    required this.usageAmount,
    required this.meterName,
  });

  factory ElectricityUsageRecord.fromJson(Map<String, dynamic> json) =>
      _$ElectricityUsageRecordFromJson(json);

  Map<String, dynamic> toJson() => _$ElectricityUsageRecordToJson(this);
}
