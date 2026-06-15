import 'package:dio/dio.dart';

import '../../models/backend/uni_response.dart';
import '../../models/ykt/transaction_record.dart';
import '../../utils/error_handler.dart';
import '../../utils/retry_handler.dart';
import '../aufe/connector.dart';
import '../logger_service.dart';
import 'ykt_config.dart';

/// 一卡通消费记录服务
///
/// 提供校园卡消费记录查询功能
class TransactionService {
  final AUFEConnection connection;
  final YKTConfig config;

  /// API端点常量
  static const Map<String, String> endpoints = {
    'queryTransactions': '/queryUserCostList.action',
  };

  TransactionService(this.connection, this.config);

  /// 查询消费记录
  ///
  /// [startDate] 起始日期，格式：YYYY-MM-DD
  /// [endDate] 终止日期，格式：YYYY-MM-DD
  ///
  /// 返回包含消费记录列表的响应
  Future<UniResponse<TransactionQueryResult>> getTransactions({
    required String startDate,
    required String endDate,
  }) async {
    try {
      // 消费记录查询很慢，只重试1次
      return await RetryHandler.retry(
        operation: () async =>
            await _performGetTransactions(startDate, endDate),
        retryIf: RetryHandler.shouldRetryOnError,
        maxAttempts: 1,
        onRetry: (attempt, error) {
          LoggerService.warning('💳 查询消费记录失败，正在重试 (尝试 $attempt/1): $error');
        },
      );
    } catch (e) {
      LoggerService.error('💳 查询消费记录失败', error: e);
      return ErrorHandler.handleError(e, '查询消费记录失败');
    }
  }

  /// 执行查询消费记录的实际操作
  Future<UniResponse<TransactionQueryResult>> _performGetTransactions(
    String startDate,
    String endDate,
  ) async {
    try {
      final url = config.toFullUrl(endpoints['queryTransactions']!);
      LoggerService.info('💳 正在查询消费记录: $url ($startDate ~ $endDate)');

      final response = await connection.client.post(
        url,
        data: {
          'startDate': startDate,
          'endDate': endDate,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {
            'Accept':
                'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
            'Upgrade-Insecure-Requests': '1',
          },
          // 消费记录查询可能很慢，设置较长的超时时间
          sendTimeout: const Duration(seconds: 600),
          receiveTimeout: const Duration(seconds: 600),
        ),
      );

      // 解析响应数据
      final data = response.data;
      if (data == null) {
        throw Exception('响应数据为空');
      }

      // 响应是HTML格式
      if (data is! String) {
        throw Exception('响应数据格式错误：期望HTML字符串，实际类型: ${data.runtimeType}');
      }

      // 从HTML中解析消费记录
      final result = TransactionQueryResult.fromHtml(data, startDate, endDate);

      LoggerService.info('💳 消费记录查询成功: 共${result.count}条记录');
      return UniResponse.success(result, message: '消费记录查询成功');
    } on DioException catch (e) {
      LoggerService.error('💳 网络请求失败', error: e);
      rethrow;
    } catch (e) {
      LoggerService.error('💳 解析响应数据失败', error: e);
      rethrow;
    }
  }

  /// 查询最近7天的消费记录
  Future<UniResponse<TransactionQueryResult>> getRecentTransactions() async {
    final now = DateTime.now();
    final startDate = now.subtract(const Duration(days: 7));

    final startDateStr = _formatDate(startDate);
    final endDateStr = _formatDate(now);

    return getTransactions(startDate: startDateStr, endDate: endDateStr);
  }

  /// 查询最近30天的消费记录
  Future<UniResponse<TransactionQueryResult>> getMonthlyTransactions() async {
    final now = DateTime.now();
    final startDate = now.subtract(const Duration(days: 30));

    final startDateStr = _formatDate(startDate);
    final endDateStr = _formatDate(now);

    return getTransactions(startDate: startDateStr, endDate: endDateStr);
  }

  /// 格式化日期为 YYYY-MM-DD
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
