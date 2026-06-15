import 'dart:convert';

import 'package:dio/dio.dart';
import '../../models/backend/uni_response.dart';
import '../../models/jwc/academic_info.dart';
import '../../models/jwc/training_plan_info.dart';
import '../../utils/error_handler.dart';
import '../../utils/retry_handler.dart';
import '../aufe/connector.dart';
import '../logger_service.dart';
import 'jwc_config.dart';

/// 学术信息服务
///
/// 提供学业信息和培养方案信息的查询功能
class AcademicService {
  final AUFEConnection connection;
  final JWCConfig config;

  /// API端点常量
  static const Map<String, String> endpoints = {
    'academicInfo': '/main/academicInfo?sf_request_type=ajax',
    'trainingPlan': '/main/showPyfaInfo?sf_request_type=ajax',
  };

  AcademicService(this.connection, this.config);

  /// 获取学业信息
  ///
  /// 返回包含已修课程数、不及格课程数、绩点、待修课程数等信息的响应
  ///
  /// 成功时返回 UniResponse.success，包含 AcademicInfo 数据
  /// 失败时返回 UniResponse.failure，根据错误类型设置 retryable 标志
  Future<UniResponse<AcademicInfo>> getAcademicInfo() async {
    try {
      return await RetryHandler.retry(
        operation: () async => await _performGetAcademicInfo(),
        retryIf: RetryHandler.shouldRetryOnError,
        maxAttempts: 3,
        onRetry: (attempt, error) {
          LoggerService.warning('📚 获取学业信息失败，正在重试 (尝试 $attempt/3): $error');
        },
      );
    } catch (e) {
      LoggerService.error('📚 获取学业信息失败', error: e);
      return ErrorHandler.handleError(e, '获取学业信息失败');
    }
  }

  /// 执行获取学业信息的实际操作
  Future<UniResponse<AcademicInfo>> _performGetAcademicInfo() async {
    try {
      final url = config.toFullUrl(endpoints['academicInfo']!);
      LoggerService.info('📚 正在获取学业信息: $url');

      final response = await connection.client.post(
        url,
        options: Options(contentType: Headers.formUrlEncodedContentType),
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

      // 后端返回的是数组格式，取第一个元素
      if (data is! List || data.isEmpty) {
        throw Exception('响应数据格式错误：期望数组格式，实际类型: ${data.runtimeType}');
      }

      final firstElement = data[0];
      if (firstElement is! Map<String, dynamic>) {
        throw Exception('响应数据格式错误：数组元素应为对象');
      }

      // 将响应数据转换为 AcademicInfo
      final academicInfo = AcademicInfo.fromJson(firstElement);

      LoggerService.info('📚 学业信息获取成功');
      return UniResponse.success(academicInfo, message: '学业信息获取成功');
    } on DioException catch (e) {
      LoggerService.error('📚 网络请求失败', error: e);
      rethrow;
    } catch (e) {
      LoggerService.error('📚 解析响应数据失败', error: e);
      rethrow;
    }
  }

  /// 获取培养方案信息
  ///
  /// 返回包含培养方案名称、专业名称、年级等信息的响应
  ///
  /// 成功时返回 UniResponse.success，包含 TrainingPlanInfo 数据
  /// 失败时返回 UniResponse.failure，根据错误类型设置 retryable 标志
  Future<UniResponse<TrainingPlanInfo>> getTrainingPlanInfo() async {
    try {
      return await RetryHandler.retry(
        operation: () async => await _performGetTrainingPlanInfo(),
        retryIf: RetryHandler.shouldRetryOnError,
        maxAttempts: 3,
        onRetry: (attempt, error) {
          LoggerService.warning('📋 获取培养方案信息失败，正在重试 (尝试 $attempt/3): $error');
        },
      );
    } catch (e) {
      LoggerService.error('📋 获取培养方案信息失败', error: e);
      return ErrorHandler.handleError(e, '获取培养方案信息失败');
    }
  }

  /// 执行获取培养方案信息的实际操作
  Future<UniResponse<TrainingPlanInfo>> _performGetTrainingPlanInfo() async {
    try {
      final url = config.toFullUrl(endpoints['trainingPlan']!);
      LoggerService.info('📋 正在获取培养方案信息: $url');

      final response = await connection.client.get(url);

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

      // 提取data字段中的数组
      final dataList = data['data'] as List?;
      if (dataList == null || dataList.isEmpty) {
        throw Exception('响应数据中没有培养方案信息');
      }

      // 获取第一个培养方案的信息数组 [培养方案名称, 专业代码]
      final planArray = dataList[0] as List?;
      if (planArray == null || planArray.length < 2) {
        throw Exception('培养方案数据格式错误');
      }

      // 从培养方案名称中提取年级和专业名称
      // 格式: "2024级网络与新媒体本科培养方案"
      final planName = planArray[0] as String;
      // final majorCode = planArray[1] as String; // 专业代码暂不使用

      // 提取年级（前4位数字）
      final gradeMatch = RegExp(r'(\d{4})级').firstMatch(planName);
      final grade = gradeMatch?.group(1) ?? '';

      // 提取专业名称（去掉年级和"本科培养方案"等后缀）
      var majorName = planName
          .replaceAll(RegExp(r'\d{4}级'), '')
          .replaceAll('本科培养方案', '')
          .replaceAll('培养方案', '')
          .trim();

      // 将响应数据转换为 TrainingPlanInfo
      final trainingPlanInfo = TrainingPlanInfo(
        planName: planName,
        majorName: majorName,
        grade: grade,
      );

      LoggerService.info('📋 培养方案信息获取成功');
      return UniResponse.success(trainingPlanInfo, message: '培养方案信息获取成功');
    } on DioException catch (e) {
      LoggerService.error('📋 网络请求失败', error: e);
      rethrow;
    } catch (e) {
      LoggerService.error('📋 解析响应数据失败', error: e);
      rethrow;
    }
  }
}
