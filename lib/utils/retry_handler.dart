import 'dart:math';

/// 重试处理器，支持指数退避策略
class RetryHandler {
  static const int maxRetries = 3;
  static const Duration initialDelay = Duration(seconds: 1);
  static const double exponentialBase = 2.0;

  /// 执行带重试的异步操作
  ///
  /// [operation] 要执行的异步操作
  /// [retryIf] 可选的条件函数，返回true时才重试
  /// [maxAttempts] 最大尝试次数，默认为3次
  /// [onRetry] 可选的重试回调，参数为当前尝试次数和错误
  static Future<T> retry<T>({
    required Future<T> Function() operation,
    bool Function(dynamic error)? retryIf,
    int maxAttempts = maxRetries,
    void Function(int attempt, dynamic error)? onRetry,
  }) async {
    int attempt = 0;

    while (true) {
      try {
        attempt++;
        return await operation();
      } catch (e) {
        // 检查是否应该重试
        if (attempt >= maxAttempts || (retryIf != null && !retryIf(e))) {
          rethrow;
        }

        // 计算延迟时间（指数退避）
        final delay = initialDelay * pow(exponentialBase, attempt - 1);

        // 调用重试回调
        if (onRetry != null) {
          onRetry(attempt, e);
        }

        // 等待后重试
        await Future.delayed(delay);
      }
    }
  }

  /// 判断错误是否应该重试（网络相关错误）
  static bool shouldRetryOnError(dynamic error) {
    // 可以根据具体错误类型判断是否应该重试
    // 例如：网络超时、连接失败等应该重试
    // 认证失败、参数错误等不应该重试
    final errorStr = error.toString().toLowerCase();

    // 应该重试的错误类型
    if (errorStr.contains('timeout') ||
        errorStr.contains('connection') ||
        errorStr.contains('network') ||
        errorStr.contains('socket')) {
      return true;
    }

    // 不应该重试的错误类型
    if (errorStr.contains('authentication') ||
        errorStr.contains('unauthorized') ||
        errorStr.contains('forbidden') ||
        errorStr.contains('invalid')) {
      return false;
    }

    // 默认重试
    return true;
  }
}
