import '../../models/jwc/score_record.dart';
import '../../models/jwc/plan_completion_info.dart';
import '../../models/aac/aac_credit_info.dart';

/// CSV导出器接口
///
/// 定义跨平台CSV导出的统一接口
abstract class CsvExporterInterface {
  /// 导出学期成绩为CSV
  ///
  /// [scores] 成绩记录列表
  /// [termId] 学期ID
  Future<void> exportTermScores(List<ScoreRecord> scores, String termId);

  /// 导出爱安财详细分数为CSV
  ///
  /// [categories] 爱安财分类列表
  Future<void> exportAACScores(List<AACCreditCategory> categories);

  /// 导出培养方案完成情况为CSV
  ///
  /// [planInfo] 培养方案完成信息
  Future<void> exportPlanCompletionInfo(PlanCompletionInfo planInfo);
}
