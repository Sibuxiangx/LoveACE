import 'package:json_annotation/json_annotation.dart';

part 'term_item.g.dart';

/// 学期信息项
///
/// 包含学期代码、名称和是否为当前学期的标识
@JsonSerializable()
class TermItem {
  /// 学期代码，如 "2023-2024-1-1"
  @JsonKey(name: 'term_code')
  final String termCode;

  /// 学期名称，如 "2023-2024上学期"
  @JsonKey(name: 'term_name')
  final String termName;

  /// 是否为当前学期
  @JsonKey(name: 'is_current')
  final bool isCurrent;

  TermItem({
    required this.termCode,
    required this.termName,
    required this.isCurrent,
  });

  factory TermItem.fromJson(Map<String, dynamic> json) =>
      _$TermItemFromJson(json);

  Map<String, dynamic> toJson() => _$TermItemToJson(this);
}
