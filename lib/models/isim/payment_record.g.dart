// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'payment_record.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PaymentRecord _$PaymentRecordFromJson(Map<String, dynamic> json) =>
    PaymentRecord(
      paymentTime: json['payment_time'] as String,
      amount: (json['amount'] as num).toDouble(),
      paymentType: json['payment_type'] as String,
    );

Map<String, dynamic> _$PaymentRecordToJson(PaymentRecord instance) =>
    <String, dynamic>{
      'payment_time': instance.paymentTime,
      'amount': instance.amount,
      'payment_type': instance.paymentType,
    };
