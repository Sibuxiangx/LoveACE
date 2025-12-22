import 'dart:convert';

import 'package:dio/dio.dart';

import '../../models/backend/uni_response.dart';
import '../../models/jwc/student_schedule.dart';
import '../../utils/error_handler.dart';
import '../../utils/retry_handler.dart';
import '../aufe/connector.dart';
import '../logger_service.dart';
import 'jwc_config.dart';

/// 学生课表服务
///
/// 提供获取学生指定学期课表的功能
class StudentScheduleService {
  final AUFEConnection connection;
  final JWCConfig config;

  /// 缓存的动态路径
  String? _cachedDynamicPath;

  /// API端点常量
  static const Map<String, String> endpoints = {
    'scheduleIndex': '/student/courseSelect/calendarSemesterCurriculum/index',
    'scheduleData':
        '/student/courseSelect/thisSemesterCurriculum/{dynamicPath}/ajaxStudentSchedule/past/callback',
  };

  StudentScheduleService(this.connection, this.config);

  /// 获取指定学期的学生课表
  ///
  /// [termCode] 学期代码，如 "2025-2026-2-1"
  ///
  /// 成功时返回 UniResponse.success，包含 StudentScheduleResponse 数据
  /// 失败时返回 UniResponse.failure，根据错误类型设置 retryable 标志
  Future<UniResponse<StudentScheduleResponse>> getStudentSchedule(
    String termCode,
  ) async {
    try {
      return await RetryHandler.retry(
        operation: () async => await _performGetStudentSchedule(termCode),
        retryIf: RetryHandler.shouldRetryOnError,
        maxAttempts: 3,
        onRetry: (attempt, error) {
          LoggerService.warning('📅 获取学生课表失败，正在重试 (尝试 $attempt/3): $error');
        },
      );
    } catch (e) {
      LoggerService.error('📅 获取学生课表失败', error: e);
      return ErrorHandler.handleError(e, '获取学生课表失败');
    }
  }

  /// 执行获取学生课表的实际操作
  Future<UniResponse<StudentScheduleResponse>> _performGetStudentSchedule(
    String termCode,
  ) async {
    try {
      LoggerService.info('📅 正在获取学生课表，学期代码: $termCode');

      // 步骤1: 获取动态路径（如果没有缓存）
      if (_cachedDynamicPath == null) {
        await _fetchDynamicPath();
      }

      if (_cachedDynamicPath == null) {
        throw Exception('未能获取动态路径参数');
      }

      // 步骤2: 请求课表数据
      final scheduleUrl = config.toFullUrl(
        endpoints['scheduleData']!.replaceAll('{dynamicPath}', _cachedDynamicPath!),
      );
      LoggerService.info('📅 正在请求课表数据: $scheduleUrl');

      final indexUrl = config.toFullUrl(endpoints['scheduleIndex']!);

      final response = await connection.client.post(
        scheduleUrl,
        data: '&planCode=$termCode',
        options: Options(
          headers: {
            'Referer': indexUrl,
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
            'X-Requested-With': 'XMLHttpRequest',
            'Accept': 'application/json, text/javascript, */*; q=0.01',
          },
        ),
      );

      // 解析响应数据
      var data = response.data;
      if (data == null) {
        throw Exception('响应数据为空');
      }

      // 如果响应是字符串，需要手动解析JSON
      if (data is String) {
        try {
          data = jsonDecode(data);
        } catch (e) {
          throw Exception('JSON解析失败: $e');
        }
      }

      // 检查响应格式
      if (data is! Map<String, dynamic>) {
        throw Exception('响应数据格式错误：期望对象格式，实际类型: ${data.runtimeType}');
      }

      // 检查错误消息
      final errorMessage = data['errorMessage'] as String? ?? '';
      if (errorMessage.isNotEmpty) {
        LoggerService.warning('📅 服务器返回错误: $errorMessage');
        throw Exception('服务器返回错误: $errorMessage');
      }

      // 解析响应
      final scheduleResponse = StudentScheduleResponse.fromJson(data);

      LoggerService.info(
        '📅 学生课表获取成功，共 ${scheduleResponse.courses.length} 门课程，总学分: ${scheduleResponse.allUnits}',
      );
      return UniResponse.success(scheduleResponse, message: '学生课表获取成功');
    } on DioException catch (e) {
      // 如果是动态路径过期，清除缓存重试
      _cachedDynamicPath = null;
      LoggerService.error('📅 网络请求失败', error: e);
      rethrow;
    } catch (e) {
      LoggerService.error('📅 解析响应数据失败', error: e);
      rethrow;
    }
  }

  /// 获取动态路径
  Future<void> _fetchDynamicPath() async {
    final indexUrl = config.toFullUrl(endpoints['scheduleIndex']!);
    LoggerService.info('📅 正在获取课表页面动态路径: $indexUrl');

    final response = await connection.client.get(indexUrl);

    var htmlContent = response.data;
    if (htmlContent == null) {
      throw Exception('课表页面响应数据为空');
    }

    if (htmlContent is! String) {
      htmlContent = htmlContent.toString();
    }

    // 从JavaScript代码中提取动态路径参数
    // 查找类似 "/student/courseSelect/thisSemesterCurriculum/625lL1p0iv/ajaxStudentSchedule"
    final pathPattern = RegExp(
      r'/student/courseSelect/thisSemesterCurriculum/([A-Za-z0-9]+)/ajaxStudentSchedule',
    );
    final pathMatch = pathPattern.firstMatch(htmlContent);

    if (pathMatch != null) {
      _cachedDynamicPath = pathMatch.group(1);
      LoggerService.info('📅 获取到动态路径: $_cachedDynamicPath');
    } else {
      LoggerService.error('📅 未能从页面中提取动态路径');
      throw Exception('未能从页面中提取动态路径参数');
    }
  }

  /// 清除缓存的动态路径
  void clearCache() {
    _cachedDynamicPath = null;
  }
}
