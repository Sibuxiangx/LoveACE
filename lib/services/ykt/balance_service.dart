import 'package:dio/dio.dart';

import '../../models/backend/uni_response.dart';
import '../../models/ykt/card_balance.dart';
import '../../utils/error_handler.dart';
import '../../utils/retry_handler.dart';
import '../aufe/connector.dart';
import '../logger_service.dart';
import 'ykt_config.dart';

/// 一卡通余额服务
///
/// 提供校园卡余额查询功能
class BalanceService {
  final AUFEConnection connection;
  final YKTConfig config;

  /// API端点常量
  static const Map<String, String> endpoints = {
    'queryBalance': '/queryUserBalances.action',
  };

  BalanceService(this.connection, this.config);

  /// 初始化一卡通会话
  ///
  /// 访问CAS登录页面以建立会话
  Future<UniResponse<void>> initSession() async {
    try {
      return await RetryHandler.retry(
        operation: () async => await _performInitSession(),
        retryIf: RetryHandler.shouldRetryOnError,
        maxAttempts: 3,
        onRetry: (attempt, error) {
          LoggerService.warning('💳 初始化一卡通会话失败，正在重试 (尝试 $attempt/3): $error');
        },
      );
    } catch (e) {
      LoggerService.error('💳 初始化一卡通会话失败', error: e);
      return ErrorHandler.handleError(e, '初始化一卡通会话失败');
    }
  }

  /// 执行初始化会话的实际操作
  Future<UniResponse<void>> _performInitSession() async {
    try {
      final url = config.casLoginUrl;
      LoggerService.info('💳 正在初始化一卡通会话: $url');

      await connection.client.get(url);

      LoggerService.info('💳 一卡通会话初始化成功');
      return UniResponse.success(null, message: '一卡通会话初始化成功');
    } on DioException catch (e) {
      LoggerService.error('💳 网络请求失败', error: e);
      rethrow;
    } catch (e) {
      LoggerService.error('💳 初始化会话失败', error: e);
      rethrow;
    }
  }

  /// 查询校园卡余额
  ///
  /// 返回包含校园卡余额信息的响应
  ///
  /// 成功时返回 UniResponse.success，包含 CardBalance 数据
  /// 失败时返回 UniResponse.failure，根据错误类型设置 retryable 标志
  Future<UniResponse<CardBalance>> getBalance() async {
    try {
      return await RetryHandler.retry(
        operation: () async => await _performGetBalance(),
        retryIf: RetryHandler.shouldRetryOnError,
        maxAttempts: 3,
        onRetry: (attempt, error) {
          LoggerService.warning('💳 查询余额失败，正在重试 (尝试 $attempt/3): $error');
        },
      );
    } catch (e) {
      LoggerService.error('💳 查询余额失败', error: e);
      return ErrorHandler.handleError(e, '查询余额失败');
    }
  }

  /// 执行查询余额的实际操作
  Future<UniResponse<CardBalance>> _performGetBalance() async {
    try {
      final url = config.toFullUrl(endpoints['queryBalance']!);
      LoggerService.info('💳 正在查询校园卡余额: $url');

      final response = await connection.client.get(
        url,
        options: Options(
          headers: {
            'Accept':
                'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
            'Upgrade-Insecure-Requests': '1',
          },
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

      // 从HTML中解析余额
      final cardBalance = CardBalance.fromHtml(data);

      LoggerService.info('💳 校园卡余额查询成功: ${cardBalance.balanceText}');
      return UniResponse.success(cardBalance, message: '余额查询成功');
    } on DioException catch (e) {
      LoggerService.error('💳 网络请求失败', error: e);
      rethrow;
    } catch (e) {
      LoggerService.error('💳 解析响应数据失败', error: e);
      rethrow;
    }
  }
}
