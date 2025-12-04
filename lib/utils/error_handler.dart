import 'dart:io';
import 'dart:async';
import '../models/backend/uni_response.dart';

/// 错误处理工具类
///
/// 提供统一的错误处理逻辑，判断错误是否可重试，并返回 UniResponse
class ErrorHandler {
  /// 处理错误并返回 UniResponse
  ///
  /// 根据错误类型判断是否可重试：
  /// - 网络超时、连接失败等错误可重试
  /// - 5xx 服务器错误可重试
  /// - 认证失败、权限不足、参数错误等不可重试
  ///
  /// [error] 捕获的错误对象
  /// [message] 用户友好的错误消息
  /// 返回包含错误信息和可重试标志的 UniResponse
  static UniResponse<T> handleError<T>(dynamic error, String message) {
    // 判断是否为可重试的错误
    bool retryable = false;
    String errorDetail = '';

    if (error is SocketException) {
      errorDetail = '网络连接失败';
      retryable = true;
    } else if (error is TimeoutException) {
      errorDetail = '请求超时';
      retryable = true;
    } else if (error is HttpException) {
      errorDetail = error.message;
      retryable = true;
    } else if (error is FormatException) {
      errorDetail = '数据格式错误';
      retryable = false;
    } else {
      final errorStr = error.toString().toLowerCase();
      errorDetail = error.toString();

      if (errorStr.contains('timeout') ||
          errorStr.contains('connection') ||
          errorStr.contains('network') ||
          errorStr.contains('socket')) {
        retryable = true;
      }
    }

    return UniResponse.failure(
      errorDetail,
      message: message,
      retryable: retryable,
    );
  }

  /// 判断错误是否为网络相关错误
  ///
  /// [error] 要判断的错误对象
  /// 返回 true 表示是网络错误，false 表示不是
  static bool isNetworkError(dynamic error) {
    if (error is SocketException ||
        error is TimeoutException ||
        error is HttpException) {
      return true;
    }

    final errorStr = error.toString().toLowerCase();
    return errorStr.contains('timeout') ||
        errorStr.contains('connection') ||
        errorStr.contains('network') ||
        errorStr.contains('socket');
  }

  /// 获取用户友好的错误消息
  ///
  /// [error] 错误对象
  /// [defaultMessage] 默认消息
  /// 返回用户友好的错误描述
  static String getUserFriendlyMessage(
    dynamic error, {
    String defaultMessage = '操作失败',
  }) {
    if (error is SocketException) {
      return '网络连接失败，请检查网络';
    } else if (error is TimeoutException) {
      return '操作超时，请重试';
    } else if (error is HttpException) {
      return '服务器错误，请稍后重试';
    } else if (error is FormatException) {
      return '数据格式错误';
    }

    final errorStr = error.toString().toLowerCase();
    if (errorStr.contains('timeout')) {
      return '操作超时，请重试';
    } else if (errorStr.contains('connection') ||
        errorStr.contains('network')) {
      return '网络连接失败，请检查网络';
    }

    return defaultMessage;
  }

  // 私有构造函数，防止实例化
  ErrorHandler._();
}
