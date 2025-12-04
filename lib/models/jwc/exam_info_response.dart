import 'package:json_annotation/json_annotation.dart';
import 'exam_info.dart';

part 'exam_info_response.g.dart';

/// 考试信息响应模型
///
/// 包含考试列表和总数
@JsonSerializable()
class ExamInfoResponse {
  @JsonKey(name: 'exams')
  final List<UnifiedExamInfo> exams; // 考试列表

  @JsonKey(name: 'total_count')
  final int totalCount; // 考试总数

  ExamInfoResponse({
    required this.exams,
    required this.totalCount,
  });

  factory ExamInfoResponse.fromJson(Map<String, dynamic> json) =>
      _$ExamInfoResponseFromJson(json);

  Map<String, dynamic> toJson() => _$ExamInfoResponseToJson(this);
}
