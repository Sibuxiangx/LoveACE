import 'package:json_annotation/json_annotation.dart';

part 'score_record.g.dart';

/// 成绩记录
///
/// 包含课程信息、成绩、学分等详细信息
@JsonSerializable()
class ScoreRecord {
  /// 序号
  @JsonKey(name: 'sequence')
  final int sequence;

  /// 学期ID
  @JsonKey(name: 'term_id')
  final String termId;

  /// 课程代码
  @JsonKey(name: 'course_code')
  final String courseCode;

  /// 课程班级
  @JsonKey(name: 'course_class')
  final String courseClass;

  /// 课程名称（中文）
  @JsonKey(name: 'course_name_cn')
  final String courseNameCn;

  /// 课程名称（英文）
  @JsonKey(name: 'course_name_en')
  final String courseNameEn;

  /// 学分
  @JsonKey(name: 'credits')
  final String credits;

  /// 学时
  @JsonKey(name: 'hours')
  final int hours;

  /// 课程性质
  @JsonKey(name: 'course_type')
  final String? courseType;

  /// 考试性质
  @JsonKey(name: 'exam_type')
  final String? examType;

  /// 成绩
  @JsonKey(name: 'score')
  final String score;

  /// 重修成绩
  @JsonKey(name: 'retake_score')
  final String? retakeScore;

  /// 补考成绩
  @JsonKey(name: 'makeup_score')
  final String? makeupScore;

  ScoreRecord({
    required this.sequence,
    required this.termId,
    required this.courseCode,
    required this.courseClass,
    required this.courseNameCn,
    required this.courseNameEn,
    required this.credits,
    required this.hours,
    this.courseType,
    this.examType,
    required this.score,
    this.retakeScore,
    this.makeupScore,
  });

  factory ScoreRecord.fromJson(Map<String, dynamic> json) =>
      _$ScoreRecordFromJson(json);

  Map<String, dynamic> toJson() => _$ScoreRecordToJson(this);
}
