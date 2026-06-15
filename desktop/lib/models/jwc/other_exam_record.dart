import 'package:json_annotation/json_annotation.dart';

part 'other_exam_record.g.dart';

/// 其他考试记录模型（中间模型）
///
/// 用于解析其他考试 API 返回的数据
@JsonSerializable()
class OtherExamRecord {
  @JsonKey(name: 'ZXJXJHH')
  final String termCode; // 学期代码

  @JsonKey(name: 'ZXJXJHM')
  final String termName; // 学期名称

  @JsonKey(name: 'KSMC')
  final String examName; // 考试名称

  @JsonKey(name: 'KCH')
  final String courseCode; // 课程代码

  @JsonKey(name: 'KCM')
  final String courseName; // 课程名称

  @JsonKey(name: 'KXH')
  final String classNumber; // 课序号

  @JsonKey(name: 'XH')
  final String studentId; // 学号

  @JsonKey(name: 'XM')
  final String studentName; // 姓名

  @JsonKey(name: 'KSDD')
  final String examLocation; // 考试地点

  @JsonKey(name: 'KSRQ')
  final String examDate; // 考试日期

  @JsonKey(name: 'KSSJ')
  final String examTime; // 考试时间

  @JsonKey(name: 'BZ')
  final String note; // 备注

  @JsonKey(name: 'RN')
  final String rowNumber; // 行号

  OtherExamRecord({
    required this.termCode,
    required this.termName,
    required this.examName,
    required this.courseCode,
    required this.courseName,
    required this.classNumber,
    required this.studentId,
    required this.studentName,
    required this.examLocation,
    required this.examDate,
    required this.examTime,
    required this.note,
    required this.rowNumber,
  });

  factory OtherExamRecord.fromJson(Map<String, dynamic> json) =>
      _$OtherExamRecordFromJson(json);

  Map<String, dynamic> toJson() => _$OtherExamRecordToJson(this);
}
