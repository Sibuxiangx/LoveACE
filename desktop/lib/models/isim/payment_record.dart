import 'package:json_annotation/json_annotation.dart';

part 'payment_record.g.dart';

/// 充值记录模型
///
/// 包含充值时间、金额和充值类型
@JsonSerializable()
class PaymentRecord {
  /// 充值时间 "YYYY-MM-DD HH:MM:SS"
  @JsonKey(name: 'payment_time')
  final String paymentTime;

  /// 充值金额（元）
  final double amount;

  /// 充值类型（下发补助/一卡通充值）
  @JsonKey(name: 'payment_type')
  final String paymentType;

  PaymentRecord({
    required this.paymentTime,
    required this.amount,
    required this.paymentType,
  });

  factory PaymentRecord.fromJson(Map<String, dynamic> json) =>
      _$PaymentRecordFromJson(json);

  Map<String, dynamic> toJson() => _$PaymentRecordToJson(this);
}
