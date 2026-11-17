import 'package:json_annotation/json_annotation.dart';

part 'plan_option.g.dart';

/// 培养方案选项
///
/// 用于多培养方案用户选择培养方案时使用
@JsonSerializable()
class PlanOption {
  /// 方案计划号（用于请求具体方案）
  @JsonKey(name: 'plan_id')
  final String planId;

  /// 方案名称
  @JsonKey(name: 'plan_name')
  final String planName;

  /// 方案类型（主修/辅修）
  @JsonKey(name: 'plan_type')
  final String planType;

  /// 是否为当前使用的方案
  @JsonKey(name: 'is_current')
  final bool isCurrent;

  PlanOption({
    required this.planId,
    required this.planName,
    required this.planType,
    this.isCurrent = false,
  });

  /// 从JSON创建实例
  factory PlanOption.fromJson(Map<String, dynamic> json) =>
      _$PlanOptionFromJson(json);

  /// 转换为JSON
  Map<String, dynamic> toJson() => _$PlanOptionToJson(this);
}

/// 培养方案选择响应
///
/// 当用户有多个培养方案时，返回此对象让用户选择
@JsonSerializable()
class PlanSelectionResponse {
  /// 可选的培养方案列表
  final List<PlanOption> options;

  /// 提示信息
  final String? hint;

  PlanSelectionResponse({
    required this.options,
    this.hint,
  });

  /// 从JSON创建实例
  factory PlanSelectionResponse.fromJson(Map<String, dynamic> json) =>
      _$PlanSelectionResponseFromJson(json);

  /// 转换为JSON
  Map<String, dynamic> toJson() => _$PlanSelectionResponseToJson(this);
}
