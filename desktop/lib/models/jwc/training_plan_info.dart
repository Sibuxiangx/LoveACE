import 'package:json_annotation/json_annotation.dart';

part 'training_plan_info.g.dart';

/// 培养方案信息数据模型
@JsonSerializable()
class TrainingPlanInfo {
  /// 培养方案名称
  final String planName;

  /// 专业名称
  final String majorName;

  /// 年级
  final String grade;

  TrainingPlanInfo({
    required this.planName,
    required this.majorName,
    required this.grade,
  });

  /// 从JSON创建实例
  factory TrainingPlanInfo.fromJson(Map<String, dynamic> json) =>
      _$TrainingPlanInfoFromJson(json);

  /// 转换为JSON
  Map<String, dynamic> toJson() => _$TrainingPlanInfoToJson(this);
}
