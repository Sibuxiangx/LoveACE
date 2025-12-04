import 'package:json_annotation/json_annotation.dart';

part 'exam_info.g.dart';

/// 统一考试信息模型
///
/// 聚合校统考和其他考试的统一格式数据
@JsonSerializable()
class UnifiedExamInfo {
  @JsonKey(name: 'course_name')
  final String courseName; // 课程名称

  @JsonKey(name: 'exam_date')
  final String examDate; // 考试日期 (YYYY-MM-DD)

  @JsonKey(name: 'exam_time')
  final String examTime; // 考试时间 (HH:MM-HH:MM)

  @JsonKey(name: 'exam_location')
  final String examLocation; // 考试地点

  @JsonKey(name: 'exam_type')
  final String examType; // 考试类型 ("校统考" | "其他考试")

  @JsonKey(name: 'note')
  final String note; // 备注（座位号等）

  UnifiedExamInfo({
    required this.courseName,
    required this.examDate,
    required this.examTime,
    required this.examLocation,
    required this.examType,
    required this.note,
  });

  factory UnifiedExamInfo.fromJson(Map<String, dynamic> json) =>
      _$UnifiedExamInfoFromJson(json);

  Map<String, dynamic> toJson() => _$UnifiedExamInfoToJson(this);
}
