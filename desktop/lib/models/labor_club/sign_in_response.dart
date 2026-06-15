import 'package:json_annotation/json_annotation.dart';

part 'sign_in_response.g.dart';

/// 签到响应
///
/// 包含签到结果的状态码、消息和数据
@JsonSerializable()
class SignInResponse {
  /// 响应状态码（0表示成功）
  @JsonKey(name: 'code')
  final int code;

  /// 响应消息
  @JsonKey(name: 'msg')
  final String msg;

  /// 响应数据
  @JsonKey(name: 'data')
  final dynamic data;

  SignInResponse({required this.code, required this.msg, this.data});

  /// 是否签到成功
  bool get isSuccess => code == 0;

  factory SignInResponse.fromJson(Map<String, dynamic> json) =>
      _$SignInResponseFromJson(json);

  Map<String, dynamic> toJson() => _$SignInResponseToJson(this);
}
