import 'package:json_annotation/json_annotation.dart';

part 'aac_credit_info.g.dart';

/// 爱安财总分信息
@JsonSerializable()
class AACCreditInfo {
  /// 总分（已四舍五入）
  @JsonKey(name: 'TotalScore')
  final double totalScore;

  /// 是否达到毕业要求
  @JsonKey(name: 'IsTypeAdopt')
  final bool isTypeAdopt;

  /// 未达到毕业要求的原因
  @JsonKey(name: 'TypeAdoptResult')
  final String typeAdoptResult;

  AACCreditInfo({
    required this.totalScore,
    required this.isTypeAdopt,
    required this.typeAdoptResult,
  });

  factory AACCreditInfo.fromJson(Map<String, dynamic> json) =>
      _$AACCreditInfoFromJson(json);

  Map<String, dynamic> toJson() => _$AACCreditInfoToJson(this);
}

/// 爱安财分数明细条目
@JsonSerializable()
class AACCreditItem {
  /// 条目ID
  @JsonKey(name: 'ID')
  final String id;

  /// 条目标题
  @JsonKey(name: 'Title')
  final String title;

  /// 条目类别名称
  @JsonKey(name: 'TypeName')
  final String typeName;

  /// 用户编号（学号）
  @JsonKey(name: 'UserNo')
  final String userNo;

  /// 分数
  @JsonKey(name: 'Score')
  final double score;

  /// 添加时间
  @JsonKey(name: 'AddTime')
  final String addTime;

  AACCreditItem({
    required this.id,
    required this.title,
    required this.typeName,
    required this.userNo,
    required this.score,
    required this.addTime,
  });

  factory AACCreditItem.fromJson(Map<String, dynamic> json) =>
      _$AACCreditItemFromJson(json);

  Map<String, dynamic> toJson() => _$AACCreditItemToJson(this);
}

/// 爱安财分数类别
@JsonSerializable()
class AACCreditCategory {
  /// 类别ID
  @JsonKey(name: 'ID')
  final String id;

  /// 显示序号
  @JsonKey(name: 'ShowNum')
  final int showNum;

  /// 类别名称
  @JsonKey(name: 'TypeName')
  final String typeName;

  /// 类别总分
  @JsonKey(name: 'TotalScore')
  final double totalScore;

  /// 该类别下的分数明细列表
  @JsonKey(name: 'children')
  final List<AACCreditItem> children;

  AACCreditCategory({
    required this.id,
    required this.showNum,
    required this.typeName,
    required this.totalScore,
    required this.children,
  });

  factory AACCreditCategory.fromJson(Map<String, dynamic> json) =>
      _$AACCreditCategoryFromJson(json);

  Map<String, dynamic> toJson() => _$AACCreditCategoryToJson(this);
}
