// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transaction_record.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TransactionRecord _$TransactionRecordFromJson(Map<String, dynamic> json) =>
    TransactionRecord(
      accountingTime: json['accountingTime'] as String,
      transactionTime: json['transactionTime'] as String,
      expense: (json['expense'] as num?)?.toDouble(),
      income: (json['income'] as num?)?.toDouble(),
      operationType: json['operationType'] as String,
      balance: (json['balance'] as num).toDouble(),
      area: json['area'] as String,
      terminalId: json['terminalId'] as String,
    );

Map<String, dynamic> _$TransactionRecordToJson(TransactionRecord instance) =>
    <String, dynamic>{
      'accountingTime': instance.accountingTime,
      'transactionTime': instance.transactionTime,
      'expense': instance.expense,
      'income': instance.income,
      'operationType': instance.operationType,
      'balance': instance.balance,
      'area': instance.area,
      'terminalId': instance.terminalId,
    };

TransactionQueryResult _$TransactionQueryResultFromJson(
  Map<String, dynamic> json,
) => TransactionQueryResult(
  records: (json['records'] as List<dynamic>)
      .map((e) => TransactionRecord.fromJson(e as Map<String, dynamic>))
      .toList(),
  startDate: json['startDate'] as String,
  endDate: json['endDate'] as String,
);

Map<String, dynamic> _$TransactionQueryResultToJson(
  TransactionQueryResult instance,
) => <String, dynamic>{
  'records': instance.records,
  'startDate': instance.startDate,
  'endDate': instance.endDate,
};
