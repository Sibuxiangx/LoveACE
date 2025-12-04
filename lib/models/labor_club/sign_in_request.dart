import 'package:json_annotation/json_annotation.dart';

part 'sign_in_request.g.dart';

/// 签到请求
///
/// 包含二维码内容和地理位置信息
@JsonSerializable()
class SignInRequest {
  /// 二维码内容
  @JsonKey(name: 'content')
  final String content;

  /// 地理位置（格式：经度,纬度）
  @JsonKey(name: 'location')
  final String location;

  SignInRequest({required this.content, required this.location});

  factory SignInRequest.fromJson(Map<String, dynamic> json) =>
      _$SignInRequestFromJson(json);

  Map<String, dynamic> toJson() => _$SignInRequestToJson(this);
}
