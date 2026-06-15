// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'other_exam_record.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

OtherExamRecord _$OtherExamRecordFromJson(Map<String, dynamic> json) =>
    OtherExamRecord(
      termCode: json['ZXJXJHH'] as String,
      termName: json['ZXJXJHM'] as String,
      examName: json['KSMC'] as String,
      courseCode: json['KCH'] as String,
      courseName: json['KCM'] as String,
      classNumber: json['KXH'] as String,
      studentId: json['XH'] as String,
      studentName: json['XM'] as String,
      examLocation: json['KSDD'] as String,
      examDate: json['KSRQ'] as String,
      examTime: json['KSSJ'] as String,
      note: json['BZ'] as String,
      rowNumber: json['RN'] as String,
    );

Map<String, dynamic> _$OtherExamRecordToJson(OtherExamRecord instance) =>
    <String, dynamic>{
      'ZXJXJHH': instance.termCode,
      'ZXJXJHM': instance.termName,
      'KSMC': instance.examName,
      'KCH': instance.courseCode,
      'KCM': instance.courseName,
      'KXH': instance.classNumber,
      'XH': instance.studentId,
      'XM': instance.studentName,
      'KSDD': instance.examLocation,
      'KSRQ': instance.examDate,
      'KSSJ': instance.examTime,
      'BZ': instance.note,
      'RN': instance.rowNumber,
    };
