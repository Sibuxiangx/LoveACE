import 'package:json_annotation/json_annotation.dart';

part 'sign_item.g.dart';

/// 签到项
///
/// 包含签到的类型、时间范围和签到状态
@JsonSerializable()
class SignItem {
  /// 签到项ID
  @JsonKey(name: 'ID')
  final String id;

  /// 签到类型（1=签到）
  @JsonKey(name: 'Type')
  final int type;

  /// 签到类型名称
  @JsonKey(name: 'TypeName')
  final String typeName;

  /// 签到开始时间
  @JsonKey(name: 'StartTime')
  final String startTime;

  /// 签到结束时间
  @JsonKey(name: 'EndTime')
  final String endTime;

  /// 是否已签到
  @JsonKey(name: 'IsSign')
  final bool isSign;

  /// 签到时间（已签到时有值）
  @JsonKey(name: 'SignTime')
  final String? signTime;

  SignItem({
    required this.id,
    required this.type,
    required this.typeName,
    required this.startTime,
    required this.endTime,
    required this.isSign,
    this.signTime,
  });

  /// 是否已签到
  bool get isSigned => isSign;

  /// 签到状态文本
  String get statusText => isSign ? '已签到' : '未签到';

  factory SignItem.fromJson(Map<String, dynamic> json) =>
      _$SignItemFromJson(json);

  Map<String, dynamic> toJson() => _$SignItemToJson(this);
}

/// 签到列表响应
@JsonSerializable()
class SignListResponse {
  /// 响应代码
  @JsonKey(name: 'code')
  final int code;

  /// 签到列表数据
  @JsonKey(name: 'data', defaultValue: [])
  final List<SignItem> data;

  SignListResponse({required this.code, required this.data});

  factory SignListResponse.fromJson(Map<String, dynamic> json) =>
      _$SignListResponseFromJson(json);

  Map<String, dynamic> toJson() => _$SignListResponseToJson(this);
}
