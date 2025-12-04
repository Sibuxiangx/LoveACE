// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'electricity_balance.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ElectricityBalance _$ElectricityBalanceFromJson(Map<String, dynamic> json) =>
    ElectricityBalance(
      remainingPurchased: (json['remaining_purchased'] as num).toDouble(),
      remainingSubsidy: (json['remaining_subsidy'] as num).toDouble(),
    );

Map<String, dynamic> _$ElectricityBalanceToJson(ElectricityBalance instance) =>
    <String, dynamic>{
      'remaining_purchased': instance.remainingPurchased,
      'remaining_subsidy': instance.remainingSubsidy,
    };
