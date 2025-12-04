// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'aac_credit_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AACCreditInfo _$AACCreditInfoFromJson(Map<String, dynamic> json) =>
    AACCreditInfo(
      totalScore: (json['TotalScore'] as num).toDouble(),
      isTypeAdopt: json['IsTypeAdopt'] as bool,
      typeAdoptResult: json['TypeAdoptResult'] as String,
    );

Map<String, dynamic> _$AACCreditInfoToJson(AACCreditInfo instance) =>
    <String, dynamic>{
      'TotalScore': instance.totalScore,
      'IsTypeAdopt': instance.isTypeAdopt,
      'TypeAdoptResult': instance.typeAdoptResult,
    };

AACCreditItem _$AACCreditItemFromJson(Map<String, dynamic> json) =>
    AACCreditItem(
      id: json['ID'] as String,
      title: json['Title'] as String,
      typeName: json['TypeName'] as String,
      userNo: json['UserNo'] as String,
      score: (json['Score'] as num).toDouble(),
      addTime: json['AddTime'] as String,
    );

Map<String, dynamic> _$AACCreditItemToJson(AACCreditItem instance) =>
    <String, dynamic>{
      'ID': instance.id,
      'Title': instance.title,
      'TypeName': instance.typeName,
      'UserNo': instance.userNo,
      'Score': instance.score,
      'AddTime': instance.addTime,
    };

AACCreditCategory _$AACCreditCategoryFromJson(Map<String, dynamic> json) =>
    AACCreditCategory(
      id: json['ID'] as String,
      showNum: (json['ShowNum'] as num).toInt(),
      typeName: json['TypeName'] as String,
      totalScore: (json['TotalScore'] as num).toDouble(),
      children: (json['children'] as List<dynamic>)
          .map((e) => AACCreditItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$AACCreditCategoryToJson(AACCreditCategory instance) =>
    <String, dynamic>{
      'ID': instance.id,
      'ShowNum': instance.showNum,
      'TypeName': instance.typeName,
      'TotalScore': instance.totalScore,
      'children': instance.children,
    };
