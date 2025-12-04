import 'package:json_annotation/json_annotation.dart';

part 'exam_schedule_item.g.dart';

/// 考试日程项模型（中间模型）
///
/// 用于解析校统考 API 返回的日程数据
@JsonSerializable()
class ExamScheduleItem {
  final String title; // 考试标题（包含课程名、时间、地点等，用 \n 分隔）
  final String start; // 考试日期 (YYYY-MM-DD)
  final String color; // 显示颜色

  ExamScheduleItem({
    required this.title,
    required this.start,
    required this.color,
  });

  factory ExamScheduleItem.fromJson(Map<String, dynamic> json) =>
      _$ExamScheduleItemFromJson(json);

  Map<String, dynamic> toJson() => _$ExamScheduleItemToJson(this);
}
