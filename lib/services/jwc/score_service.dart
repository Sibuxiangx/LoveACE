import 'dart:convert';

import 'package:dio/dio.dart';

import '../../models/backend/uni_response.dart';
import '../../models/jwc/score_record.dart';
import '../../models/jwc/term_score_response.dart';
import '../../utils/error_handler.dart';
import '../../utils/retry_handler.dart';
import '../aufe/connector.dart';
import '../logger_service.dart';
import 'jwc_config.dart';

/// 成绩查询服务
///
/// 提供学期成绩查询功能
class ScoreService {
  final AUFEConnection connection;
  final JWCConfig config;

  /// API端点常量
  static const Map<String, String> endpoints = {
    'termScorePre': '/student/integratedQuery/scoreQuery/allTermScores/index',
    'termScore':
        '/student/integratedQuery/scoreQuery/{dynamicPath}/allTermScores/data',
  };

  ScoreService(this.connection, this.config);

  /// 获取指定学期的成绩列表
  ///
  /// 先访问成绩查询页面获取动态路径参数，然后使用该路径请求成绩数据
  ///
  /// [termCode] 学期代码，如 "2023-2024-1-1"
  ///
  /// 成功时返回 UniResponse.success，包含 TermScoreResponse 数据
  /// 失败时返回 UniResponse.failure，根据错误类型设置 retryable 标志
  Future<UniResponse<TermScoreResponse>> getTermScore(String termCode) async {
    try {
      return await RetryHandler.retry(
        operation: () async => await _performGetTermScore(termCode),
        retryIf: RetryHandler.shouldRetryOnError,
        maxAttempts: 3,
        onRetry: (attempt, error) {
          LoggerService.warning('📊 获取学期成绩失败，正在重试 (尝试 $attempt/3): $error');
        },
      );
    } catch (e) {
      LoggerService.error('📊 获取学期成绩失败', error: e);
      return ErrorHandler.handleError(e, '获取学期成绩失败');
    }
  }

  /// 执行获取学期成绩的实际操作
  Future<UniResponse<TermScoreResponse>> _performGetTermScore(
    String termCode,
  ) async {
    try {
      LoggerService.info('📊 正在获取学期成绩，学期代码: $termCode');

      // 步骤1: 访问成绩查询页面，提取动态路径参数
      final preUrl = config.toFullUrl(endpoints['termScorePre']!);
      LoggerService.info('📊 正在访问成绩查询页面: $preUrl');

      final preResponse = await connection.client.get(preUrl);

      // 解析HTML响应，提取动态路径
      var htmlContent = preResponse.data;
      if (htmlContent == null) {
        throw Exception('成绩查询页面响应数据为空');
      }

      // 如果响应不是字符串，尝试转换
      if (htmlContent is! String) {
        htmlContent = htmlContent.toString();
      }

      // 从JavaScript代码中提取动态路径参数
      // 查找类似 "M1uwxk14o6" 的路径参数
      // 通常在JavaScript中包含 "/allTermScores/data" 的路径

      String? dynamicPath;

      // 在JavaScript代码中查找包含 "allTermScores/data" 的路径
      final pathPattern = RegExp(r'/([A-Za-z0-9]+)/allTermScores/data');
      final pathMatch = pathPattern.firstMatch(htmlContent);

      if (pathMatch != null) {
        dynamicPath = pathMatch.group(1);
        LoggerService.info('📊 从JavaScript提取到动态路径: $dynamicPath');
      }

      if (dynamicPath == null) {
        LoggerService.error(
          '📊 未能提取动态路径，HTML内容前500字符: ${htmlContent.substring(0, htmlContent.length > 500 ? 500 : htmlContent.length)}',
        );
        throw Exception('未能从页面中提取动态路径参数');
      }

      LoggerService.info('📊 最终使用的动态路径: $dynamicPath');

      // 步骤2: 使用动态路径和学期代码请求成绩数据
      final scoreUrl = config.toFullUrl(
        endpoints['termScore']!.replaceAll('{dynamicPath}', dynamicPath),
      );
      LoggerService.info('📊 正在请求成绩数据: $scoreUrl');

      // 构建请求参数
      final requestData = {
        'zxjxjhh': termCode, // 执行教学计划号（学期代码）
        'kch': '', // 课程号（空表示查询所有）
        'kcm': '', // 课程名（空表示查询所有）
        'pageNum': '1', // 页码
        'pageSize': '50', // 每页数量
        'sf_request_type': 'ajax', // 必需：标识这是Ajax请求
      };

      LoggerService.info('📊 请求参数: $requestData');
      LoggerService.info('📊 Referer: $preUrl');

      final scoreResponse = await connection.client.post(
        scoreUrl,
        data: requestData,
        options: Options(
          headers: {
            'Referer': preUrl,
            'Content-Type': 'application/x-www-form-urlencoded',
          },
        ),
      );

      // 解析成绩数据响应
      var data = scoreResponse.data;
      if (data == null) {
        throw Exception('成绩数据响应为空');
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

      // 检查是否有错误响应
      if (data['result'] == 'error') {
        final errorMsg = data['msg'] ?? '未知错误';
        LoggerService.warning('📊 服务器返回错误: $errorMsg');
        throw Exception('服务器返回错误: $errorMsg');
      }

      // 提取list对象
      final listData = data['list'] as Map<String, dynamic>?;
      if (listData == null) {
        LoggerService.info('📊 该学期暂无成绩记录');
        return UniResponse.success(
          TermScoreResponse(totalCount: 0, records: []),
          message: '该学期暂无成绩记录',
        );
      }

      // 提取成绩记录列表
      final recordsList = listData['records'] as List?;
      if (recordsList == null || recordsList.isEmpty) {
        // 空数据情况，返回空列表而不是错误
        LoggerService.info('📊 该学期暂无成绩记录');
        return UniResponse.success(
          TermScoreResponse(totalCount: 0, records: []),
          message: '该学期暂无成绩记录',
        );
      }

      // 解析成绩记录
      final records = <ScoreRecord>[];
      for (final recordData in recordsList) {
        // 数据格式是数组: [序号, 学期, 课程代码, 班级, 课程名(中), 课程名(英), 学分, 学时, 课程类型, 考试类型, 成绩, 重修成绩, 补考成绩]
        if (recordData is! List || recordData.length < 11) {
          LoggerService.warning('📊 跳过格式错误的成绩记录: $recordData');
          continue;
        }

        try {
          // 将数组数据映射到模型字段
          final mappedData = {
            'sequence': recordData[0] as int? ?? 0,
            'term_id': recordData[1]?.toString() ?? '',
            'course_code': recordData[2]?.toString() ?? '',
            'course_class': recordData[3]?.toString() ?? '',
            'course_name_cn': recordData[4]?.toString() ?? '',
            'course_name_en': recordData[5]?.toString() ?? '',
            'credits': recordData[6]?.toString() ?? '0',
            'hours': int.tryParse(recordData[7]?.toString() ?? '0') ?? 0,
            'course_type': recordData[8]?.toString(),
            'exam_type': recordData[9]?.toString(),
            'score': recordData[10]?.toString() ?? '',
            'retake_score': recordData.length > 11
                ? recordData[11]?.toString()
                : null,
            'makeup_score': recordData.length > 12
                ? recordData[12]?.toString()
                : null,
          };

          final record = ScoreRecord.fromJson(mappedData);
          records.add(record);
        } catch (e) {
          LoggerService.warning('📊 解析成绩记录失败: $e, 数据: $recordData');
          continue;
        }
      }

      // 从pageContext中获取总数
      final pageContext = listData['pageContext'] as Map<String, dynamic>?;
      final totalCount = pageContext?['totalCount'] as int? ?? records.length;

      final response = TermScoreResponse(
        totalCount: totalCount,
        records: records,
      );

      LoggerService.info('📊 学期成绩获取成功，共 ${records.length} 条记录');
      return UniResponse.success(response, message: '学期成绩获取成功');
    } catch (e) {
      LoggerService.error('📊 网络请求失败', error: e);
      rethrow;
    }
  }
}
