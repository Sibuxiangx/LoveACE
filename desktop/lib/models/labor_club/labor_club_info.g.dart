// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'labor_club_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LaborClubInfo _$LaborClubInfoFromJson(Map<String, dynamic> json) =>
    LaborClubInfo(
      id: json['ID'] as String,
      name: json['Name'] as String,
      typeName: json['TypeName'] as String?,
      ico: json['Ico'] as String?,
      chairmanName: json['CairmanName'] as String?,
      memberNum: (json['MemberNum'] as num).toInt(),
    );

Map<String, dynamic> _$LaborClubInfoToJson(LaborClubInfo instance) =>
    <String, dynamic>{
      'ID': instance.id,
      'Name': instance.name,
      'TypeName': instance.typeName,
      'Ico': instance.ico,
      'CairmanName': instance.chairmanName,
      'MemberNum': instance.memberNum,
    };
