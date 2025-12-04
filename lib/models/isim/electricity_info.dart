import 'package:json_annotation/json_annotation.dart';
import 'electricity_balance.dart';
import 'electricity_usage_record.dart';
import 'payment_record.dart';

part 'electricity_info.g.dart';

/// 电费信息包装模型
///
/// 包含余额、用电记录和充值记录
@JsonSerializable()
class ElectricityInfo {
  /// 电费余额
  final ElectricityBalance balance;

  /// 用电记录列表
  @JsonKey(name: 'usage_records')
  final List<ElectricityUsageRecord> usageRecords;

  /// 充值记录列表
  final List<PaymentRecord> payments;

  ElectricityInfo({
    required this.balance,
    required this.usageRecords,
    required this.payments,
  });

  factory ElectricityInfo.fromJson(Map<String, dynamic> json) =>
      _$ElectricityInfoFromJson(json);

  Map<String, dynamic> toJson() => _$ElectricityInfoToJson(this);
}
