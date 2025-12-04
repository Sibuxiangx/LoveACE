import 'package:json_annotation/json_annotation.dart';
import 'award_project.dart';
import 'credits_summary.dart';

part 'competition_full_response.g.dart';

/// 竞赛完整信息响应数据模型
@JsonSerializable()
class CompetitionFullResponse {
  /// 学生ID/工号
  @JsonKey(name: 'student_id')
  final String studentId;

  /// 获奖项目总数
  @JsonKey(name: 'total_awards_count')
  final int totalAwardsCount;

  /// 获奖项目列表
  final List<AwardProject> awards;

  /// 学分汇总
  @JsonKey(name: 'credits_summary')
  final CreditsSummary? creditsSummary;

  CompetitionFullResponse({
    required this.studentId,
    this.totalAwardsCount = 0,
    this.awards = const [],
    this.creditsSummary,
  });

  /// 从JSON创建实例
  factory CompetitionFullResponse.fromJson(Map<String, dynamic> json) =>
      _$CompetitionFullResponseFromJson(json);

  /// 转换为JSON
  Map<String, dynamic> toJson() => _$CompetitionFullResponseToJson(this);
}
