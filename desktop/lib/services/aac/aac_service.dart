import 'dart:convert';
import 'package:dio/dio.dart';
import '../../models/backend/uni_response.dart';
import '../../models/aac/aac_credit_info.dart';
import '../../models/aufe/login_status.dart';
import '../../utils/error_handler.dart';
import '../../utils/retry_handler.dart';
import '../aufe/connector.dart';
import '../logger_service.dart';
import 'aac_config.dart';
import 'aac_ticket_manager.dart';

/// 爱安财 Service
///
/// 提供爱安财系统的查询功能
class AACService {
  final AUFEConnection connection;
  final AACConfig config;

  /// API 端点常量
  static const Map<String, String> endpoints = {
    'totalScore': '/User/Center/DoGetScoreInfo?sf_request_type=ajax',
    'scoreList': '/User/Center/DoGetScoreList?sf_request_type=ajax',
  };

  AACService(this.connection, this.config);

  /// 获取AAC ticket（如果不存在则自动获取）
  Future<String?> _getOrFetchTicket() async {
    // 先尝试从存储中获取
    String? ticket = await AACTicketManager.getTicket(connection.userId);

    if (ticket != null && ticket.isNotEmpty) {
      LoggerService.info('📦 使用已存储的AAC ticket');
      return ticket;
    }

    // 如果不存在，则获取新的ticket
    LoggerService.info('🌐 开始获取新的AAC ticket');
    ticket = await _fetchTicketFromServer();

    if (ticket != null && ticket.isNotEmpty) {
      // 保存到存储
      await AACTicketManager.saveTicket(connection.userId, ticket);
      LoggerService.info('💾 已保存新的AAC ticket');
      return ticket;
    }

    return null;
  }

  /// 从服务器获取ticket
  Future<String?> _fetchTicketFromServer() async {
    try {
      String nextLocation = AACConfig.loginServiceUrl;
      int redirectCount = 0;
      const int maxRedirects = 10;

      while (redirectCount < maxRedirects) {
        // 使用不自动跳转的client来获取重定向信息
        final response = await connection.simpleClient.get(
          nextLocation,
          options: Options(
            followRedirects: false,
            validateStatus: (status) => status! < 400,
          ),
        );

        // 检查是否是重定向
        if (response.statusCode == 302 ||
            response.statusCode == 301 ||
            response.statusCode == 303 ||
            response.statusCode == 307 ||
            response.statusCode == 308) {
          nextLocation = response.headers.value('location') ?? '';

          if (nextLocation.isEmpty) {
            LoggerService.error('❌ 重定向响应中缺少 Location 头');
            return null;
          }

          LoggerService.info('🔄 重定向到: $nextLocation');

          // 学校强制改密拦截：CAS 校验通过但不签发票据，302 到改密页面。不是密码错误，不可重试
          if (nextLocation.contains('/mng/acp/completeInfo/password')) {
            LoggerService.warning('🏫 检测到学校强制改密拦截，停止获取 ticket');
            throw PasswordChangeRequiredException();
          }

          redirectCount++;

          // 检查是否到达注册页面（包含ticket）
          if (nextLocation.contains('register?ticket=')) {
            LoggerService.info('✅ 找到AAC ticket');
            final ticket = _extractTicket(nextLocation);
            return ticket;
          }
        } else {
          break;
        }
      }

      if (redirectCount >= maxRedirects) {
        LoggerService.error('❌ 重定向次数过多');
      }

      return null;
    } on PasswordChangeRequiredException {
      rethrow;
    } catch (e) {
      LoggerService.error('❌ 获取AAC ticket失败', error: e);
      return null;
    }
  }

  /// 从URL中提取ticket
  String? _extractTicket(String url) {
    try {
      // URL格式: http://dekt-ac-acxk-net.vpn2.aufe.edu.cn:8118/#/register?ticket=xxx
      // 需要处理#后面的部分

      // 先检查是否包含ticket参数
      if (!url.contains('ticket=')) {
        LoggerService.error('❌ URL中没有找到ticket参数');
        return null;
      }

      // 提取ticket值
      final ticketStart = url.indexOf('ticket=') + 7;
      String ticket = url.substring(ticketStart);

      // 如果后面还有其他参数，截取到&或#为止
      final ampersandIndex = ticket.indexOf('&');
      if (ampersandIndex != -1) {
        ticket = ticket.substring(0, ampersandIndex);
      }

      final hashIndex = ticket.indexOf('#');
      if (hashIndex != -1) {
        ticket = ticket.substring(0, hashIndex);
      }

      if (ticket.isEmpty) {
        LoggerService.error('❌ 提取的ticket为空');
        return null;
      }

      // URL解码
      final decodedTicket = Uri.decodeComponent(ticket);
      LoggerService.info(
        '✅ 成功提取ticket: ${decodedTicket.substring(0, decodedTicket.length > 20 ? 20 : decodedTicket.length)}...',
      );

      return decodedTicket;
    } catch (e) {
      LoggerService.error('❌ 解析ticket失败', error: e);
      return null;
    }
  }

  /// 获取爱安财总分信息
  ///
  /// 返回包含总分、达成状态和详细信息的响应
  ///
  /// 成功时返回 UniResponse.success，包含 AACCreditInfo 数据
  /// 失败时返回 UniResponse.failure，根据错误类型设置 retryable 标志
  Future<UniResponse<AACCreditInfo>> getCreditInfo() async {
    try {
      return await RetryHandler.retry(
        operation: () async => await _performGetCreditInfo(),
        retryIf: RetryHandler.shouldRetryOnError,
        maxAttempts: 3,
        onRetry: (attempt, error) {
          LoggerService.warning('💰 获取爱安财总分信息失败，正在重试 (尝试 $attempt/3): $error');
        },
      );
    } catch (e) {
      LoggerService.error('💰 获取爱安财总分信息失败', error: e);
      return ErrorHandler.handleError(e, '获取爱安财总分信息失败');
    }
  }

  /// 执行获取总分信息的实际操作
  Future<UniResponse<AACCreditInfo>> _performGetCreditInfo() async {
    try {
      final url = config.toFullUrl(endpoints['totalScore']!);
      LoggerService.info('💰 正在获取爱安财总分信息: $url');

      // 获取ticket
      final ticket = await _getOrFetchTicket();
      if (ticket == null) {
        throw Exception('无法获取AAC ticket');
      }

      final response = await connection.simpleClient.post(
        url,
        data: {},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'ticket': ticket, 'sdp-app-session': connection.twfId},
        ),
      );

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: 服务器响应异常');
      }

      var data = response.data;
      if (data == null) {
        throw Exception('响应数据为空');
      }

      if (data is String) {
        try {
          data = jsonDecode(data);
        } catch (e) {
          throw Exception('JSON解析失败: $e');
        }
      }

      if (data is! Map<String, dynamic>) {
        throw Exception('响应数据格式错误');
      }

      final code = data['code'];
      if (code != 0) {
        throw Exception('服务器返回错误代码: $code');
      }

      final creditData = data['data'];
      if (creditData == null) {
        throw Exception('响应数据中没有data字段');
      }

      final creditInfo = AACCreditInfo.fromJson(creditData);
      LoggerService.info('💰 爱安财总分信息获取成功');
      return UniResponse.success(creditInfo, message: '获取爱安财总分信息成功');
    } on DioException catch (e) {
      LoggerService.error('💰 网络请求失败', error: e);
      rethrow;
    } catch (e) {
      LoggerService.error('💰 解析响应数据失败', error: e);
      rethrow;
    }
  }

  /// 获取爱安财分数明细列表
  ///
  /// 返回包含分数分类和明细的响应
  ///
  /// 成功时返回 UniResponse.success，包含 List<AACCreditCategory> 数据
  /// 失败时返回 UniResponse.failure，根据错误类型设置 retryable 标志
  Future<UniResponse<List<AACCreditCategory>>> getCreditList() async {
    try {
      return await RetryHandler.retry(
        operation: () async => await _performGetCreditList(),
        retryIf: RetryHandler.shouldRetryOnError,
        maxAttempts: 3,
        onRetry: (attempt, error) {
          LoggerService.warning('💰 获取爱安财分数明细失败，正在重试 (尝试 $attempt/3): $error');
        },
      );
    } catch (e) {
      LoggerService.error('💰 获取爱安财分数明细失败', error: e);
      return ErrorHandler.handleError(e, '获取爱安财分数明细失败');
    }
  }

  /// 执行获取分数明细的实际操作
  Future<UniResponse<List<AACCreditCategory>>> _performGetCreditList() async {
    try {
      final url = config.toFullUrl(endpoints['scoreList']!);
      LoggerService.info('💰 正在获取爱安财分数明细: $url');

      // 获取ticket
      final ticket = await _getOrFetchTicket();
      if (ticket == null) {
        throw Exception('无法获取AAC ticket');
      }

      final response = await connection.simpleClient.post(
        url,
        data: {'pageIndex': '1', 'pageSize': '100'},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'ticket': ticket, 'sdp-app-session': connection.twfId},
        ),
      );

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: 服务器响应异常');
      }

      var data = response.data;
      if (data == null) {
        throw Exception('响应数据为空');
      }

      if (data is String) {
        try {
          data = jsonDecode(data);
        } catch (e) {
          throw Exception('JSON解析失败: $e');
        }
      }

      if (data is! Map<String, dynamic>) {
        throw Exception('响应数据格式错误');
      }

      final code = data['code'];
      if (code != 0) {
        throw Exception('服务器返回错误代码: $code');
      }

      final listData = data['data'];
      if (listData == null) {
        throw Exception('响应数据中没有data字段');
      }

      if (listData is! List) {
        throw Exception('响应数据格式错误：data不是数组');
      }

      final categories = listData
          .map(
            (item) => AACCreditCategory.fromJson(item as Map<String, dynamic>),
          )
          .toList();

      LoggerService.info('💰 爱安财分数明细获取成功，共 ${categories.length} 个类别');
      return UniResponse.success(categories, message: '获取爱安财分数明细成功');
    } on DioException catch (e) {
      LoggerService.error('💰 网络请求失败', error: e);
      rethrow;
    } catch (e) {
      LoggerService.error('💰 解析响应数据失败', error: e);
      rethrow;
    }
  }

  /// 重置AAC ticket（用于设置页面）
  Future<void> resetTicket() async {
    await AACTicketManager.deleteTicket(connection.userId);
    LoggerService.info('🗑️ 已重置用户 ${connection.userId} 的AAC ticket');
  }
}
