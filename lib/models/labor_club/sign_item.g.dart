// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sign_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SignItem _$SignItemFromJson(Map<String, dynamic> json) => SignItem(
  id: json['ID'] as String,
  type: (json['Type'] as num).toInt(),
  typeName: json['TypeName'] as String,
  startTime: json['StartTime'] as String,
  endTime: json['EndTime'] as String,
  isSign: json['IsSign'] as bool,
  signTime: json['SignTime'] as String?,
);

Map<String, dynamic> _$SignItemToJson(SignItem instance) => <String, dynamic>{
  'ID': instance.id,
  'Type': instance.type,
  'TypeName': instance.typeName,
  'StartTime': instance.startTime,
  'EndTime': instance.endTime,
  'IsSign': instance.isSign,
  'SignTime': instance.signTime,
};

SignListResponse _$SignListResponseFromJson(Map<String, dynamic> json) =>
    SignListResponse(
      code: (json['code'] as num).toInt(),
      data:
          (json['data'] as List<dynamic>?)
              ?.map((e) => SignItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );

Map<String, dynamic> _$SignListResponseToJson(SignListResponse instance) =>
    <String, dynamic>{'code': instance.code, 'data': instance.data};
