import 'dart:convert';
import 'package:dio/dio.dart';
import '../../models/backend/uni_response.dart';
import '../../models/labor_club/labor_club_progress_info.dart';
import '../../models/aufe/login_status.dart';
import '../../models/labor_club/labor_club_activity.dart';
import '../../models/labor_club/labor_club_info.dart';
import '../../models/labor_club/activity_detail.dart';
import '../../models/labor_club/sign_in_request.dart';
import '../../models/labor_club/sign_in_response.dart';
import '../../models/labor_club/sign_item.dart';
import '../../utils/error_handler.dart';
import '../../utils/retry_handler.dart';
import '../aufe/connector.dart';
import '../logger_service.dart';
import 'ldjlb_config.dart';
import 'ldjlb_ticket_manager.dart';

/// 劳动俱乐部 Service
///
/// 提供劳动俱乐部系统的查询和操作功能
class LaborClubService {
  final AUFEConnection connection;
  final LDJLBConfig config;

  /// API 端点常量
  static const Map<String, String> endpoints = {
    'progress': '/User/Center/DoGetScoreInfo',
    'joinedActivities': '/User/Activity/DoGetJoinPageList',
    'joinedClubs': '/User/Club/DoGetJoinList',
    'clubActivities': '/User/Activity/DoGetPageList',
    'applyJoin': '/User/Activity/DoApplyJoin',
    'scanSign': '/User/Center/DoScanSignQRImage',
    'signList': '/User/Activity/DoGetSignList',
    'activityDetail': '/User/Activity/DoGetDetail',
  };

  LaborClubService(this.connection, this.config);

  /// 获取劳动俱乐部 ticket（如果不存在则自动获取）
  Future<String?> _getOrFetchTicket() async {
    // 先尝试从存储中获取
    String? ticket = await LDJLBTicketManager.getTicket(connection.userId);

    if (ticket != null && ticket.isNotEmpty) {
      LoggerService.info('📦 使用已存储的劳动俱乐部 ticket');
      return ticket;
    }

    // 如果不存在，则获取新的ticket
    LoggerService.info('🌐 开始获取新的劳动俱乐部 ticket');
    ticket = await _fetchTicketFromServer();

    if (ticket != null && ticket.isNotEmpty) {
      // 保存到存储
      await LDJLBTicketManager.saveTicket(connection.userId, ticket);
      LoggerService.info('💾 已保存新的劳动俱乐部 ticket');
      return ticket;
    }

    return null;
  }

  /// 从服务器获取ticket
  Future<String?> _fetchTicketFromServer() async {
    try {
      String nextLocation = LDJLBConfig.loginServiceUrl;
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

          // 检查是否到达回调页面（包含ticket）
          if (nextLocation.contains('register?ticket=')) {
            LoggerService.info('✅ 找到劳动俱乐部 ticket');
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
      LoggerService.error('❌ 获取劳动俱乐部 ticket失败', error: e);
      return null;
    }
  }

  /// 从URL中提取ticket
  String? _extractTicket(String url) {
    try {
      if (!url.contains('ticket=')) {
        LoggerService.error('❌ URL中没有找到ticket参数');
        return null;
      }

      final ticketStart = url.indexOf('ticket=') + 7;
      String ticket = url.substring(ticketStart);

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

  /// 重置劳动俱乐部 ticket（用于设置页面）
  Future<void> resetTicket() async {
    await LDJLBTicketManager.deleteTicket(connection.userId);
    LoggerService.info('🗑️ 已重置用户 ${connection.userId} 的劳动俱乐部 ticket');
  }

  /// 获取劳动修课进度
  Future<UniResponse<LaborClubProgressInfo>> getProgress() async {
    try {
      return await RetryHandler.retry(
        operation: () async => await _performGetProgress(),
        retryIf: RetryHandler.shouldRetryOnError,
        maxAttempts: 3,
        onRetry: (attempt, error) {
          LoggerService.warning('🏃 获取劳动修课进度失败，正在重试 (尝试 $attempt/3): $error');
        },
      );
    } catch (e) {
      LoggerService.error('🏃 获取劳动修课进度失败', error: e);
      return ErrorHandler.handleError(e, '获取劳动修课进度失败');
    }
  }

  Future<UniResponse<LaborClubProgressInfo>> _performGetProgress() async {
    try {
      final url = config.toFullUrl(endpoints['progress']!);
      LoggerService.info('🏃 正在获取劳动修课进度: $url');

      final ticket = await _getOrFetchTicket();
      if (ticket == null) {
        throw Exception('无法获取劳动俱乐部 ticket');
      }

      final response = await connection.simpleClient.post(
        url,
        data: {},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'ticket': ticket, 'sdp-app-session': connection.twfId},
        ),
      );

      var data = response.data;
      if (data == null) {
        throw Exception('响应数据为空');
      }

      if (data is String) {
        data = jsonDecode(data);
      }

      if (data is! Map<String, dynamic>) {
        throw Exception('响应数据格式错误');
      }

      final code = data['code'];
      if (code != 0) {
        throw Exception('服务器返回错误代码: $code');
      }

      final progressData = data['data'];
      if (progressData == null) {
        throw Exception('响应数据中没有data字段');
      }

      final progressInfo = LaborClubProgressInfo.fromJson(progressData);
      LoggerService.info('🏃 劳动修课进度获取成功: ${progressInfo.finishCount}/10');
      return UniResponse.success(progressInfo, message: '获取劳动修课进度成功');
    } on DioException catch (e) {
      LoggerService.error('🏃 网络请求失败', error: e);
      rethrow;
    } catch (e) {
      LoggerService.error('🏃 解析响应数据失败', error: e);
      rethrow;
    }
  }

  /// 获取已加入的活动列表
  Future<UniResponse<List<LaborClubActivity>>> getJoinedActivities() async {
    try {
      return await RetryHandler.retry(
        operation: () async => await _performGetJoinedActivities(),
        retryIf: RetryHandler.shouldRetryOnError,
        maxAttempts: 3,
        onRetry: (attempt, error) {
          LoggerService.warning('📋 获取已加入活动列表失败，正在重试 (尝试 $attempt/3): $error');
        },
      );
    } catch (e) {
      LoggerService.error('📋 获取已加入活动列表失败', error: e);
      return ErrorHandler.handleError(e, '获取已加入活动列表失败');
    }
  }

  Future<UniResponse<List<LaborClubActivity>>>
  _performGetJoinedActivities() async {
    try {
      final url = config.toFullUrl(endpoints['joinedActivities']!);
      LoggerService.info('📋 正在获取已加入活动列表: $url');

      final ticket = await _getOrFetchTicket();
      if (ticket == null) {
        throw Exception('无法获取劳动俱乐部 ticket');
      }

      final response = await connection.simpleClient.post(
        url,
        data: {'pageIndex': '1', 'pageSize': '100'},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'ticket': ticket, 'sdp-app-session': connection.twfId},
        ),
      );

      var data = response.data;
      if (data == null) {
        throw Exception('响应数据为空');
      }

      if (data is String) {
        data = jsonDecode(data);
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

      final activities = listData
          .map(
            (item) => LaborClubActivity.fromJson(item as Map<String, dynamic>),
          )
          .toList();

      LoggerService.info('📋 已加入活动列表获取成功，共 ${activities.length} 个活动');
      return UniResponse.success(activities, message: '获取已加入活动列表成功');
    } on DioException catch (e) {
      LoggerService.error('📋 网络请求失败', error: e);
      rethrow;
    } catch (e) {
      LoggerService.error('📋 解析响应数据失败', error: e);
      rethrow;
    }
  }

  /// 获取已加入的俱乐部列表
  Future<UniResponse<List<LaborClubInfo>>> getJoinedClubs() async {
    try {
      return await RetryHandler.retry(
        operation: () async => await _performGetJoinedClubs(),
        retryIf: RetryHandler.shouldRetryOnError,
        maxAttempts: 3,
        onRetry: (attempt, error) {
          LoggerService.warning(
            '🏛️ 获取已加入俱乐部列表失败，正在重试 (尝试 $attempt/3): $error',
          );
        },
      );
    } catch (e) {
      LoggerService.error('🏛️ 获取已加入俱乐部列表失败', error: e);
      return ErrorHandler.handleError(e, '获取已加入俱乐部列表失败');
    }
  }

  Future<UniResponse<List<LaborClubInfo>>> _performGetJoinedClubs() async {
    try {
      final url = config.toFullUrl(endpoints['joinedClubs']!);
      LoggerService.info('🏛️ 正在获取已加入俱乐部列表: $url');

      final ticket = await _getOrFetchTicket();
      if (ticket == null) {
        throw Exception('无法获取劳动俱乐部 ticket');
      }

      final response = await connection.simpleClient.post(
        url,
        data: {},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'ticket': ticket, 'sdp-app-session': connection.twfId},
        ),
      );

      var data = response.data;
      if (data == null) {
        throw Exception('响应数据为空');
      }

      if (data is String) {
        data = jsonDecode(data);
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

      final clubs = listData
          .map((item) => LaborClubInfo.fromJson(item as Map<String, dynamic>))
          .toList();

      LoggerService.info('🏛️ 已加入俱乐部列表获取成功，共 ${clubs.length} 个俱乐部');
      return UniResponse.success(clubs, message: '获取已加入俱乐部列表成功');
    } on DioException catch (e) {
      LoggerService.error('🏛️ 网络请求失败', error: e);
      rethrow;
    } catch (e) {
      LoggerService.error('🏛️ 解析响应数据失败', error: e);
      rethrow;
    }
  }

  /// 获取俱乐部的活动列表
  Future<UniResponse<List<LaborClubActivity>>> getClubActivities(
    String clubId, {
    int pageIndex = 1,
    int pageSize = 100,
  }) async {
    try {
      return await RetryHandler.retry(
        operation: () async => await _performGetClubActivities(
          clubId,
          pageIndex: pageIndex,
          pageSize: pageSize,
        ),
        retryIf: RetryHandler.shouldRetryOnError,
        maxAttempts: 3,
        onRetry: (attempt, error) {
          LoggerService.warning('🎯 获取俱乐部活动列表失败，正在重试 (尝试 $attempt/3): $error');
        },
      );
    } catch (e) {
      LoggerService.error('🎯 获取俱乐部活动列表失败', error: e);
      return ErrorHandler.handleError(e, '获取俱乐部活动列表失败');
    }
  }

  Future<UniResponse<List<LaborClubActivity>>> _performGetClubActivities(
    String clubId, {
    required int pageIndex,
    required int pageSize,
  }) async {
    try {
      final url = config.toFullUrl(endpoints['clubActivities']!);
      LoggerService.info('🎯 正在获取俱乐部 $clubId 的活动列表: $url');

      final ticket = await _getOrFetchTicket();
      if (ticket == null) {
        throw Exception('无法获取劳动俱乐部 ticket');
      }

      final response = await connection.simpleClient.post(
        url,
        data: {
          'clubID': clubId,
          'pageIndex': pageIndex.toString(),
          'pageSize': pageSize.toString(),
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'ticket': ticket, 'sdp-app-session': connection.twfId},
        ),
      );

      var data = response.data;
      if (data == null) {
        throw Exception('响应数据为空');
      }

      if (data is String) {
        data = jsonDecode(data);
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

      final activities = listData
          .map(
            (item) => LaborClubActivity.fromJson(item as Map<String, dynamic>),
          )
          .toList();

      LoggerService.info('🎯 俱乐部 $clubId 活动列表获取成功，共 ${activities.length} 个活动');
      return UniResponse.success(activities, message: '获取俱乐部活动列表成功');
    } on DioException catch (e) {
      LoggerService.error('🎯 网络请求失败', error: e);
      rethrow;
    } catch (e) {
      LoggerService.error('🎯 解析响应数据失败', error: e);
      rethrow;
    }
  }

  /// 报名活动
  Future<UniResponse<Map<String, dynamic>>> applyActivity(
    String activityId, {
    String reason = '',
  }) async {
    try {
      return await RetryHandler.retry(
        operation: () async =>
            await _performApplyActivity(activityId, reason: reason),
        retryIf: RetryHandler.shouldRetryOnError,
        maxAttempts: 3,
        onRetry: (attempt, error) {
          LoggerService.warning('✍️ 报名活动失败，正在重试 (尝试 $attempt/3): $error');
        },
      );
    } catch (e) {
      LoggerService.error('✍️ 报名活动失败', error: e);
      return ErrorHandler.handleError(e, '报名活动失败');
    }
  }

  Future<UniResponse<Map<String, dynamic>>> _performApplyActivity(
    String activityId, {
    required String reason,
  }) async {
    try {
      final url = config.toFullUrl(endpoints['applyJoin']!);
      LoggerService.info('✍️ 正在报名活动 $activityId: $url');

      final ticket = await _getOrFetchTicket();
      if (ticket == null) {
        throw Exception('无法获取劳动俱乐部 ticket');
      }

      final response = await connection.simpleClient.post(
        url,
        data: {'activityID': activityId, 'reason': reason},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'ticket': ticket, 'sdp-app-session': connection.twfId},
        ),
      );

      var data = response.data;
      if (data == null) {
        throw Exception('响应数据为空');
      }

      if (data is String) {
        data = jsonDecode(data);
      }

      if (data is! Map<String, dynamic>) {
        throw Exception('响应数据格式错误');
      }

      final code = data['code'];
      final msg = data['msg'] ?? '报名成功';

      if (code != 0) {
        LoggerService.warning('✍️ 报名活动失败: $msg');
        return UniResponse.failure(msg, message: '报名活动失败', retryable: false);
      }

      LoggerService.info('✍️ 报名活动成功: $msg');
      return UniResponse.success(data, message: msg);
    } on DioException catch (e) {
      LoggerService.error('✍️ 网络请求失败', error: e);
      rethrow;
    } catch (e) {
      LoggerService.error('✍️ 解析响应数据失败', error: e);
      rethrow;
    }
  }

  /// 扫码签到
  Future<UniResponse<SignInResponse>> scanSignIn(SignInRequest request) async {
    try {
      return await RetryHandler.retry(
        operation: () async => await _performScanSignIn(request),
        retryIf: RetryHandler.shouldRetryOnError,
        maxAttempts: 3,
        onRetry: (attempt, error) {
          LoggerService.warning('📷 扫码签到失败，正在重试 (尝试 $attempt/3): $error');
        },
      );
    } catch (e) {
      LoggerService.error('📷 扫码签到失败', error: e);
      return ErrorHandler.handleError(e, '扫码签到失败');
    }
  }

  Future<UniResponse<SignInResponse>> _performScanSignIn(
    SignInRequest request,
  ) async {
    try {
      final url = config.toFullUrl(endpoints['scanSign']!);
      LoggerService.info('📷 正在扫码签到: $url');

      final ticket = await _getOrFetchTicket();
      if (ticket == null) {
        throw Exception('无法获取劳动俱乐部 ticket');
      }

      final response = await connection.simpleClient.post(
        url,
        data: request.toJson(),
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'ticket': ticket, 'sdp-app-session': connection.twfId},
        ),
      );

      var data = response.data;
      if (data == null) {
        throw Exception('响应数据为空');
      }

      if (data is String) {
        data = jsonDecode(data);
      }

      if (data is! Map<String, dynamic>) {
        throw Exception('响应数据格式错误');
      }

      final signInResponse = SignInResponse.fromJson(data);

      if (signInResponse.isSuccess) {
        LoggerService.info('📷 扫码签到成功: ${signInResponse.msg}');
      } else {
        LoggerService.warning('📷 扫码签到失败: ${signInResponse.msg}');
      }

      return UniResponse.success(signInResponse, message: signInResponse.msg);
    } on DioException catch (e) {
      LoggerService.error('📷 网络请求失败', error: e);
      rethrow;
    } catch (e) {
      LoggerService.error('📷 解析响应数据失败', error: e);
      rethrow;
    }
  }

  /// 获取签到列表
  Future<UniResponse<List<SignItem>>> getSignList(
    String activityId, {
    int type = 1,
    int pageIndex = 1,
    int pageSize = 100,
  }) async {
    try {
      return await RetryHandler.retry(
        operation: () async => await _performGetSignList(
          activityId,
          type: type,
          pageIndex: pageIndex,
          pageSize: pageSize,
        ),
        retryIf: RetryHandler.shouldRetryOnError,
        maxAttempts: 3,
        onRetry: (attempt, error) {
          LoggerService.warning('📝 获取签到列表失败，正在重试 (尝试 $attempt/3): $error');
        },
      );
    } catch (e) {
      LoggerService.error('📝 获取签到列表失败', error: e);
      return ErrorHandler.handleError(e, '获取签到列表失败');
    }
  }

  Future<UniResponse<List<SignItem>>> _performGetSignList(
    String activityId, {
    required int type,
    required int pageIndex,
    required int pageSize,
  }) async {
    try {
      final url = config.toFullUrl(endpoints['signList']!);
      LoggerService.info('📝 正在获取活动 $activityId 的签到列表: $url');

      final ticket = await _getOrFetchTicket();
      if (ticket == null) {
        throw Exception('无法获取劳动俱乐部 ticket');
      }

      final response = await connection.simpleClient.post(
        url,
        data: {
          'activityID': activityId,
          'type': type,
          'pageIndex': pageIndex,
          'pageSize': pageSize,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'ticket': ticket, 'sdp-app-session': connection.twfId},
        ),
      );

      var data = response.data;
      if (data == null) {
        throw Exception('响应数据为空');
      }

      if (data is String) {
        data = jsonDecode(data);
      }

      if (data is! Map<String, dynamic>) {
        throw Exception('响应数据格式错误');
      }

      final signListResponse = SignListResponse.fromJson(data);

      if (signListResponse.code != 0) {
        throw Exception('服务器返回错误代码: ${signListResponse.code}');
      }

      final signCount = signListResponse.data.length;
      final signedCount = signListResponse.data
          .where((item) => item.isSign)
          .length;

      LoggerService.info('📝 签到列表获取成功，共 $signCount 项，已签到 $signedCount 项');
      return UniResponse.success(signListResponse.data, message: '获取签到列表成功');
    } on DioException catch (e) {
      LoggerService.error('📝 网络请求失败', error: e);
      rethrow;
    } catch (e) {
      LoggerService.error('📝 解析响应数据失败', error: e);
      rethrow;
    }
  }

  /// 获取活动详情
  Future<UniResponse<ActivityDetail>> getActivityDetail(
    String activityId,
  ) async {
    try {
      return await RetryHandler.retry(
        operation: () async => await _performGetActivityDetail(activityId),
        retryIf: RetryHandler.shouldRetryOnError,
        maxAttempts: 3,
        onRetry: (attempt, error) {
          LoggerService.warning('📄 获取活动详情失败，正在重试 (尝试 $attempt/3): $error');
        },
      );
    } catch (e) {
      LoggerService.error('📄 获取活动详情失败', error: e);
      return ErrorHandler.handleError(e, '获取活动详情失败');
    }
  }

  Future<UniResponse<ActivityDetail>> _performGetActivityDetail(
    String activityId,
  ) async {
    try {
      final url = config.toFullUrl(endpoints['activityDetail']!);
      LoggerService.info('📄 正在获取活动 $activityId 的详情: $url');

      final ticket = await _getOrFetchTicket();
      if (ticket == null) {
        throw Exception('无法获取劳动俱乐部 ticket');
      }

      final response = await connection.simpleClient.post(
        url,
        data: {'id': activityId},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'ticket': ticket, 'sdp-app-session': connection.twfId},
        ),
      );

      var data = response.data;
      if (data == null) {
        throw Exception('响应数据为空');
      }

      if (data is String) {
        data = jsonDecode(data);
      }

      if (data is! Map<String, dynamic>) {
        throw Exception('响应数据格式错误');
      }

      final code = data['code'];
      if (code != 0) {
        throw Exception('服务器返回错误代码: $code');
      }

      final detailData = data['data'];
      if (detailData == null) {
        throw Exception('响应数据中没有data字段');
      }

      // 合并 data 和其他字段（formData、flowData、teacherList 在根级别）
      final mergedData = Map<String, dynamic>.from(detailData);
      if (data['formData'] != null) {
        mergedData['formData'] = data['formData'];
      }
      if (data['flowData'] != null) {
        mergedData['flowData'] = data['flowData'];
      }
      if (data['teacherList'] != null) {
        mergedData['teacherList'] = data['teacherList'];
      }

      final activityDetail = ActivityDetail.fromJson(mergedData);
      LoggerService.info('📄 活动详情获取成功: ${activityDetail.title}');
      return UniResponse.success(activityDetail, message: '获取活动详情成功');
    } on DioException catch (e) {
      LoggerService.error('📄 网络请求失败', error: e);
      rethrow;
    } catch (e) {
      LoggerService.error('📄 解析响应数据失败', error: e);
      rethrow;
    }
  }

  /// 获取活动签到列表
}
