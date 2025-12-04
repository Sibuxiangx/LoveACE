// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'labor_club_activity.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LaborClubActivity _$LaborClubActivityFromJson(Map<String, dynamic> json) =>
    LaborClubActivity(
      id: json['ID'] as String? ?? '',
      ico: json['Ico'] as String?,
      state: (json['State'] as num?)?.toInt() ?? 0,
      stateName: json['StateName'] as String? ?? '',
      typeId: json['TypeID'] as String? ?? '',
      typeName: json['TypeName'] as String? ?? '',
      title: json['Title'] as String? ?? '',
      startTime: json['StartTime'] as String? ?? '',
      endTime: json['EndTime'] as String? ?? '',
      chargeUserNo: json['ChargeUserNo'] as String? ?? '',
      chargeUserName: json['ChargeUserName'] as String? ?? '',
      clubId: json['ClubID'] as String? ?? '',
      clubName: json['ClubName'] as String? ?? '',
      memberNum: (json['MemberNum'] as num?)?.toInt() ?? 0,
      addTime: json['AddTime'] as String? ?? '',
      peopleNum: (json['PeopleNum'] as num?)?.toInt() ?? 0,
      peopleNumMin: (json['PeopleNumMin'] as num?)?.toInt(),
      isJoined: const StringToBoolConverter().fromJson(json['IsJson']),
      isClosed: const StringToBoolConverter().fromJson(json['IsClose']),
      signUpStartTime: json['SignUpStartTime'] as String? ?? '',
      signUpEndTime: json['SignUpEndTime'] as String? ?? '',
    );

Map<String, dynamic> _$LaborClubActivityToJson(LaborClubActivity instance) =>
    <String, dynamic>{
      'ID': instance.id,
      'Ico': instance.ico,
      'State': instance.state,
      'StateName': instance.stateName,
      'TypeID': instance.typeId,
      'TypeName': instance.typeName,
      'Title': instance.title,
      'StartTime': instance.startTime,
      'EndTime': instance.endTime,
      'ChargeUserNo': instance.chargeUserNo,
      'ChargeUserName': instance.chargeUserName,
      'ClubID': instance.clubId,
      'ClubName': instance.clubName,
      'MemberNum': instance.memberNum,
      'AddTime': instance.addTime,
      'PeopleNum': instance.peopleNum,
      'PeopleNumMin': instance.peopleNumMin,
      'IsJson': const StringToBoolConverter().toJson(instance.isJoined),
      'IsClose': const StringToBoolConverter().toJson(instance.isClosed),
      'SignUpStartTime': instance.signUpStartTime,
      'SignUpEndTime': instance.signUpEndTime,
    };
