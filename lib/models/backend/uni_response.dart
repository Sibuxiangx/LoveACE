import 'package:json_annotation/json_annotation.dart';

part 'uni_response.g.dart';

/// 统一响应包装类
/// 用于包装所有API响应，提供统一的成功/失败处理机制
@JsonSerializable(genericArgumentFactories: true)
class UniResponse<T> {
  /// 请求是否成功
  final bool success;

  /// 响应数据
  final T? data;

  /// 响应消息
  final String message;

  /// 错误信息
  final String? error;

  /// 是否可重试（用于网络错误等可恢复的错误）
  final bool retryable;

  UniResponse({
    required this.success,
    this.data,
    required this.message,
    this.error,
    this.retryable = false,
  });

  /// 从JSON创建实例
  factory UniResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Object? json) fromJsonT,
  ) => _$UniResponseFromJson(json, fromJsonT);

  /// 转换为JSON
  Map<String, dynamic> toJson(Object? Function(T value) toJsonT) =>
      _$UniResponseToJson(this, toJsonT);

  /// 创建成功响应
  factory UniResponse.success(T data, {String message = '操作成功'}) {
    return UniResponse(
      success: true,
      data: data,
      message: message,
      retryable: false,
    );
  }

  /// 创建失败响应
  factory UniResponse.failure(
    String error, {
    String message = '操作失败',
    bool retryable = false,
  }) {
    return UniResponse(
      success: false,
      message: message,
      error: error,
      retryable: retryable,
    );
  }
}
