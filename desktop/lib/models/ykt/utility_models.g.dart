// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'utility_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SelectOption _$SelectOptionFromJson(Map<String, dynamic> json) =>
    SelectOption(value: json['value'] as String, name: json['name'] as String);

Map<String, dynamic> _$SelectOptionToJson(SelectOption instance) =>
    <String, dynamic>{'value': instance.value, 'name': instance.name};

StudentInfo _$StudentInfoFromJson(Map<String, dynamic> json) => StudentInfo(
  studentId: json['studentId'] as String,
  name: json['name'] as String,
  accountStatus: json['accountStatus'] as String,
  cardStatus: json['cardStatus'] as String,
  balance: (json['balance'] as num).toDouble(),
  accId: json['accId'] as String,
);

Map<String, dynamic> _$StudentInfoToJson(StudentInfo instance) =>
    <String, dynamic>{
      'studentId': instance.studentId,
      'name': instance.name,
      'accountStatus': instance.accountStatus,
      'cardStatus': instance.cardStatus,
      'balance': instance.balance,
      'accId': instance.accId,
    };

RoomSelection _$RoomSelectionFromJson(Map<String, dynamic> json) =>
    RoomSelection(
      dormId: json['dormId'] as String,
      dormName: json['dormName'] as String,
      buildingName: json['buildingName'] as String,
      floorName: json['floorName'] as String,
      roomId: json['roomId'] as String,
      roomName: json['roomName'] as String,
    );

Map<String, dynamic> _$RoomSelectionToJson(RoomSelection instance) =>
    <String, dynamic>{
      'dormId': instance.dormId,
      'dormName': instance.dormName,
      'buildingName': instance.buildingName,
      'floorName': instance.floorName,
      'roomId': instance.roomId,
      'roomName': instance.roomName,
    };

UtilityPaymentRequest _$UtilityPaymentRequestFromJson(
  Map<String, dynamic> json,
) => UtilityPaymentRequest(
  roomId: json['roomId'] as String,
  dormId: json['dormId'] as String,
  dormName: json['dormName'] as String,
  buildName: json['buildName'] as String,
  floorName: json['floorName'] as String,
  roomName: json['roomName'] as String,
  accId: json['accId'] as String,
  balances: json['balances'] as String,
  payType: json['payType'] as String? ?? '2',
  choosePayType: json['choosePayType'] as String? ?? '1',
  money: (json['money'] as num).toInt(),
);

Map<String, dynamic> _$UtilityPaymentRequestToJson(
  UtilityPaymentRequest instance,
) => <String, dynamic>{
  'roomId': instance.roomId,
  'dormId': instance.dormId,
  'dormName': instance.dormName,
  'buildName': instance.buildName,
  'floorName': instance.floorName,
  'roomName': instance.roomName,
  'accId': instance.accId,
  'balances': instance.balances,
  'payType': instance.payType,
  'choosePayType': instance.choosePayType,
  'money': instance.money,
};

UtilityPaymentResult _$UtilityPaymentResultFromJson(
  Map<String, dynamic> json,
) => UtilityPaymentResult(
  success: json['success'] as bool,
  message: json['message'] as String,
);

Map<String, dynamic> _$UtilityPaymentResultToJson(
  UtilityPaymentResult instance,
) => <String, dynamic>{
  'success': instance.success,
  'message': instance.message,
};

ElectricPurchaseRecord _$ElectricPurchaseRecordFromJson(
  Map<String, dynamic> json,
) => ElectricPurchaseRecord(
  name: json['name'] as String,
  studentId: json['studentId'] as String,
  area: json['area'] as String,
  roomInfo: json['roomInfo'] as String,
  amount: (json['amount'] as num).toDouble(),
  purchaseDate: json['purchaseDate'] as String,
  department: json['department'] as String,
);

Map<String, dynamic> _$ElectricPurchaseRecordToJson(
  ElectricPurchaseRecord instance,
) => <String, dynamic>{
  'name': instance.name,
  'studentId': instance.studentId,
  'area': instance.area,
  'roomInfo': instance.roomInfo,
  'amount': instance.amount,
  'purchaseDate': instance.purchaseDate,
  'department': instance.department,
};

ElectricPurchaseQueryResult _$ElectricPurchaseQueryResultFromJson(
  Map<String, dynamic> json,
) => ElectricPurchaseQueryResult(
  startDate: json['startDate'] as String,
  endDate: json['endDate'] as String,
  records: (json['records'] as List<dynamic>)
      .map((e) => ElectricPurchaseRecord.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$ElectricPurchaseQueryResultToJson(
  ElectricPurchaseQueryResult instance,
) => <String, dynamic>{
  'startDate': instance.startDate,
  'endDate': instance.endDate,
  'records': instance.records,
};
