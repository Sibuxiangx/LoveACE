import 'package:json_annotation/json_annotation.dart';

part 'electricity_balance.g.dart';

/// 电费余额模型
///
/// 包含剩余购电和剩余补助信息
@JsonSerializable()
class ElectricityBalance {
  /// 剩余购电（度）
  @JsonKey(name: 'remaining_purchased')
  final double remainingPurchased;

  /// 剩余补助（度）
  @JsonKey(name: 'remaining_subsidy')
  final double remainingSubsidy;

  ElectricityBalance({
    required this.remainingPurchased,
    required this.remainingSubsidy,
  });

  /// 总余额（购电 + 补助）
  double get total => remainingPurchased + remainingSubsidy;

  factory ElectricityBalance.fromJson(Map<String, dynamic> json) =>
      _$ElectricityBalanceFromJson(json);

  Map<String, dynamic> toJson() => _$ElectricityBalanceToJson(this);
}
