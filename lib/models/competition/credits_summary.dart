import 'package:json_annotation/json_annotation.dart';

part 'credits_summary.g.dart';

/// 学分汇总数据模型
@JsonSerializable()
class CreditsSummary {
  /// 学科竞赛学分
  @JsonKey(name: 'discipline_competition_credits')
  final double? disciplineCompetitionCredits;

  /// 科研项目学分
  @JsonKey(name: 'scientific_research_credits')
  final double? scientificResearchCredits;

  /// 可转竞赛类学分
  @JsonKey(name: 'transferable_competition_credits')
  final double? transferableCompetitionCredits;

  /// 创新创业实践学分
  @JsonKey(name: 'innovation_practice_credits')
  final double? innovationPracticeCredits;

  /// 能力资格认证学分
  @JsonKey(name: 'ability_certification_credits')
  final double? abilityCertificationCredits;

  /// 其他项目学分
  @JsonKey(name: 'other_project_credits')
  final double? otherProjectCredits;

  CreditsSummary({
    this.disciplineCompetitionCredits,
    this.scientificResearchCredits,
    this.transferableCompetitionCredits,
    this.innovationPracticeCredits,
    this.abilityCertificationCredits,
    this.otherProjectCredits,
  });

  /// 从JSON创建实例
  factory CreditsSummary.fromJson(Map<String, dynamic> json) =>
      _$CreditsSummaryFromJson(json);

  /// 转换为JSON
  Map<String, dynamic> toJson() => _$CreditsSummaryToJson(this);

  /// 计算总学分
  double get totalCredits {
    return (disciplineCompetitionCredits ?? 0) +
        (scientificResearchCredits ?? 0) +
        (transferableCompetitionCredits ?? 0) +
        (innovationPracticeCredits ?? 0) +
        (abilityCertificationCredits ?? 0) +
        (otherProjectCredits ?? 0);
  }

  /// 格式化学分显示
  /// 
  /// 如果学分为null，返回"无"
  /// 否则返回保留两位小数的字符串
  String formatCredit(double? credit) {
    if (credit == null) return '无';
    return credit.toStringAsFixed(2);
  }
}
