// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'activity_detail.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ActivityDetail _$ActivityDetailFromJson(Map<String, dynamic> json) =>
    ActivityDetail(
      id: json['ID'] as String,
      title: json['Title'] as String,
      startTime: json['StartTime'] as String,
      endTime: json['EndTime'] as String,
      chargeUserName: json['ChargeUserName'] as String,
      clubName: json['ClubName'] as String,
      memberNum: (json['MemberNum'] as num).toInt(),
      peopleNum: (json['PeopleNum'] as num).toInt(),
      formData:
          (json['formData'] as List<dynamic>?)
              ?.map((e) => FormField.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      flowData:
          (json['flowData'] as List<dynamic>?)
              ?.map((e) => FlowData.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      teacherList:
          (json['teacherList'] as List<dynamic>?)
              ?.map((e) => Teacher.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      signList:
          (json['SignList'] as List<dynamic>?)
              ?.map((e) => SignItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      signUpStartTime: json['SignUpStartTime'] as String?,
      signUpEndTime: json['SignUpEndTime'] as String?,
    );

Map<String, dynamic> _$ActivityDetailToJson(ActivityDetail instance) =>
    <String, dynamic>{
      'ID': instance.id,
      'Title': instance.title,
      'StartTime': instance.startTime,
      'EndTime': instance.endTime,
      'ChargeUserName': instance.chargeUserName,
      'ClubName': instance.clubName,
      'MemberNum': instance.memberNum,
      'PeopleNum': instance.peopleNum,
      'formData': instance.formData,
      'flowData': instance.flowData,
      'teacherList': instance.teacherList,
      'SignList': instance.signList,
      'SignUpStartTime': instance.signUpStartTime,
      'SignUpEndTime': instance.signUpEndTime,
    };

FormField _$FormFieldFromJson(Map<String, dynamic> json) => FormField(
  id: json['ID'] as String? ?? '',
  name: json['Name'] as String,
  isMust: json['IsMust'] as bool? ?? false,
  fieldType: (json['FieldType'] as num?)?.toInt() ?? 1,
  value: json['Value'] as String,
);

Map<String, dynamic> _$FormFieldToJson(FormField instance) => <String, dynamic>{
  'ID': instance.id,
  'Name': instance.name,
  'IsMust': instance.isMust,
  'FieldType': instance.fieldType,
  'Value': instance.value,
};

FlowData _$FlowDataFromJson(Map<String, dynamic> json) => FlowData(
  nodeName: json['FlowTypeName'] as String,
  userName: json['ExamUserName'] as String,
  isAdopt: json['IsAdopt'] as bool?,
  time: json['ExamTime'] as String,
);

Map<String, dynamic> _$FlowDataToJson(FlowData instance) => <String, dynamic>{
  'FlowTypeName': instance.nodeName,
  'ExamUserName': instance.userName,
  'IsAdopt': instance.isAdopt,
  'ExamTime': instance.time,
};

Teacher _$TeacherFromJson(Map<String, dynamic> json) => Teacher(
  name: json['UserName'] as String,
  userNo: json['UserNo'] as String? ?? '',
);

Map<String, dynamic> _$TeacherToJson(Teacher instance) => <String, dynamic>{
  'UserName': instance.name,
  'UserNo': instance.userNo,
};
