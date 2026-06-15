import 'package:json_annotation/json_annotation.dart';

part 'labor_club_info.g.dart';

/// 劳动俱乐部信息
///
/// 包含俱乐部的基本信息
@JsonSerializable()
class LaborClubInfo {
  /// 俱乐部ID
  @JsonKey(name: 'ID')
  final String id;

  /// 俱乐部名称
  @JsonKey(name: 'Name')
  final String name;

  /// 俱乐部类型名称
  @JsonKey(name: 'TypeName')
  final String? typeName;

  /// 俱乐部图标
  @JsonKey(name: 'Ico')
  final String? ico;

  /// 会长姓名（注意：API返回的字段名是 CairmanName，有拼写错误）
  @JsonKey(name: 'CairmanName')
  final String? chairmanName;

  /// 成员数量
  @JsonKey(name: 'MemberNum')
  final int memberNum;

  LaborClubInfo({
    required this.id,
    required this.name,
    this.typeName,
    this.ico,
    this.chairmanName,
    required this.memberNum,
  });

  factory LaborClubInfo.fromJson(Map<String, dynamic> json) =>
      _$LaborClubInfoFromJson(json);

  Map<String, dynamic> toJson() => _$LaborClubInfoToJson(this);
}
