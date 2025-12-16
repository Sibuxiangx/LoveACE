// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'card_balance.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CardBalance _$CardBalanceFromJson(Map<String, dynamic> json) => CardBalance(
  balance: (json['balance'] as num).toDouble(),
  balanceText: json['balanceText'] as String,
);

Map<String, dynamic> _$CardBalanceToJson(CardBalance instance) =>
    <String, dynamic>{
      'balance': instance.balance,
      'balanceText': instance.balanceText,
    };
