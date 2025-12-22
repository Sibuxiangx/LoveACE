import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import '../../models/backend/uni_response.dart';
import '../../models/jwc/course_schedule_record.dart';
import '../../utils/error_handler.dart';
import '../../utils/retry_handler.dart';
import '../aufe/connector.dart';
import '../logger_service.dart';
import 'jwc_config.dart';

/// 课程开课查询的学期项
class ScheduleTermItem {
  /// 学期代码，如 "2025-2026-1-1"
  final String termCode;

  /// 学期名称，如 "2025-2026学年秋"
  final String termName;

  /// 是否为当前选中的学期
  final bool isSelected;

  ScheduleTermItem({
    required this.termCode,
    required this.termName,
    this.isSelected = false,
  });
}

/// 课程开课查询服务
///
/// 提供根据课程号和学期查询开课情况的功能
class CourseScheduleService {
  final AUFEConnection connection;
  final JWCConfig config;

  /// API端点常量
  static const Map<String, String> endpoints = {
    'courseScheduleIndex': '/student/integratedQuery/course/courseSchdule/index',
    'courseInfo':
        '/student/integratedQuery/course/courseSchdule/courseInfo?sf_request_type=ajax',
  };

  CourseScheduleService(this.connection, this.config);

  /// 获取课程开课查询可用的学期列表
  ///
  /// 从课程安排页面解析学期选择框，提取学期代码和名称
  /// 列表第一项为当前学期（默认选中）
  ///
  /// 成功时返回 UniResponse.success，包含 List<ScheduleTermItem> 数据
  /// 失败时返回 UniResponse.failure，根据错误类型设置 retryable 标志
  Future<UniResponse<List<ScheduleTermItem>>> getScheduleTerms() async {
    try {
      return await RetryHandler.retry(
        operation: () async => await _performGetScheduleTerms(),
        retryIf: RetryHandler.shouldRetryOnError,
        maxAttempts: 3,
        onRetry: (attempt, error) {
          LoggerService.warning('📅 获取开课查询学期列表失败，正在重试 (尝试 $attempt/3): $error');
        },
      );
    } catch (e) {
      LoggerService.error('📅 获取开课查询学期列表失败', error: e);
      return ErrorHandler.handleError(e, '获取学期列表失败');
    }
  }

  /// 执行获取学期列表的实际操作
  Future<UniResponse<List<ScheduleTermItem>>> _performGetScheduleTerms() async {
    try {
      final url = config.toFullUrl(endpoints['courseScheduleIndex']!);
      LoggerService.info('📅 正在获取开课查询学期列表: $url');

      final response = await connection.client.get(url);

      // 解析HTML响应
      var htmlContent = response.data;
      if (htmlContent == null) {
        throw Exception('响应数据为空');
      }

      // 如果响应不是字符串，尝试转换
      if (htmlContent is! String) {
        htmlContent = htmlContent.toString();
      }

      // 解析HTML文档
      final document = html_parser.parse(htmlContent);

      // 查找学期选择框 (select#zxjxjhh 或 select[name="zxjxjhh"])
      final selectElement = document.querySelector('select#zxjxjhh') ??
          document.querySelector('select[name="zxjxjhh"]');
      if (selectElement == null) {
        throw Exception('未找到学期选择框 (select#zxjxjhh)');
      }

      // 提取所有option元素
      final options = selectElement.querySelectorAll('option');
      if (options.isEmpty) {
        throw Exception('学期选择框中没有选项');
      }

      // 解析学期列表
      final termList = <ScheduleTermItem>[];
      for (final option in options) {
        final termCode = option.attributes['value'];
        final termName = option.text.trim();
        final isSelected = option.attributes.containsKey('selected');

        if (termCode == null || termCode.isEmpty) {
          continue; // 跳过空值选项
        }

        termList.add(
          ScheduleTermItem(
            termCode: termCode,
            termName: termName,
            isSelected: isSelected,
          ),
        );
      }

      if (termList.isEmpty) {
        throw Exception('未能解析出任何学期信息');
      }

      LoggerService.info('📅 开课查询学期列表获取成功，共 ${termList.length} 个学期');
      return UniResponse.success(termList, message: '学期列表获取成功');
    } catch (e) {
      LoggerService.error('📅 获取学期列表失败', error: e);
      rethrow;
    }
  }

  /// 根据课程号和学期查询开课情况
  ///
  /// [courseCode] 课程号
  /// [termCode] 学期代码，如 "2025-2026-2-1"
  /// [pageNum] 页码，默认为1
  /// [pageSize] 每页数量，默认为50
  ///
  /// 成功时返回 UniResponse.success，包含 List<CourseScheduleRecord> 数据
  /// 失败时返回 UniResponse.failure，根据错误类型设置 retryable 标志
  Future<UniResponse<List<CourseScheduleRecord>>> queryCourseSchedule({
    required String courseCode,
    required String termCode,
    int pageNum = 1,
    int pageSize = 50,
  }) async {
    try {
      return await RetryHandler.retry(
        operation: () async => await _performQueryCourseSchedule(
          courseCode: courseCode,
          termCode: termCode,
          pageNum: pageNum,
          pageSize: pageSize,
        ),
        retryIf: RetryHandler.shouldRetryOnError,
        maxAttempts: 3,
        onRetry: (attempt, error) {
          LoggerService.warning('📚 查询课程开课情况失败，正在重试 (尝试 $attempt/3): $error');
        },
      );
    } catch (e) {
      LoggerService.error('📚 查询课程开课情况失败', error: e);
      return ErrorHandler.handleError(e, '查询课程开课情况失败');
    }
  }

  /// 执行查询课程开课情况的实际操作
  Future<UniResponse<List<CourseScheduleRecord>>> _performQueryCourseSchedule({
    required String courseCode,
    required String termCode,
    required int pageNum,
    required int pageSize,
  }) async {
    try {
      final url = config.toFullUrl(endpoints['courseInfo']!);
      LoggerService.info('📚 正在查询课程开课情况: $url, 课程号: $courseCode, 学期: $termCode');

      // 构建请求参数
      final formData = {
        'zxjxjhh': termCode,
        'kkxsh': '',
        'kkxqh': '',
        'jxlh': '',
        'jash': '',
        'skxq': '',
        'skjc': '',
        'kch': courseCode,
        'kcm': '',
        'kclb': '',
        'skjs': '',
        'xqname': '',
        'jcname': '',
        'jxlname': '',
        'jasname': '',
        'pageNum': pageNum.toString(),
        'pageSize': pageSize.toString(),
      };

      final response = await connection.client.post(
        url,
        data: formData,
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

      // 检查响应格式
      if (data is! Map<String, dynamic>) {
        throw Exception('响应数据格式错误：期望对象格式，实际类型: ${data.runtimeType}');
      }

      // 解析响应
      final courseResponse = CourseScheduleResponse.fromJson(data);
      final records = courseResponse.list.records;
      final totalCount = courseResponse.list.pageContext.totalCount;

      LoggerService.info('📚 课程开课查询成功，共 $totalCount 条记录，当前页 ${records.length} 条');
      return UniResponse.success(records, message: '查询成功，共 $totalCount 条记录');
    } on DioException catch (e) {
      LoggerService.error('📚 网络请求失败', error: e);
      rethrow;
    } catch (e) {
      LoggerService.error('📚 解析响应数据失败', error: e);
      rethrow;
    }
  }

  /// 查询学期全部开课情况
  ///
  /// 获取指定学期的所有开课记录（不限课程号）
  /// 使用并发请求加速获取
  ///
  /// [termCode] 学期代码，如 "2025-2026-2-1"
  /// [onProgress] 进度回调，参数为 (已完成页数, 总页数, 已获取记录数)
  ///
  /// 成功时返回 UniResponse.success，包含 List<CourseScheduleRecord> 数据
  /// 失败时返回 UniResponse.failure，根据错误类型设置 retryable 标志
  Future<UniResponse<List<CourseScheduleRecord>>> queryAllCoursesForTerm({
    required String termCode,
    void Function(int completed, int total, int records)? onProgress,
  }) async {
    try {
      return await RetryHandler.retry(
        operation: () async => await _performQueryAllCoursesForTermConcurrent(
          termCode,
          onProgress: onProgress,
        ),
        retryIf: RetryHandler.shouldRetryOnError,
        maxAttempts: 3,
        onRetry: (attempt, error) {
          LoggerService.warning('📚 查询学期全部开课失败，正在重试 (尝试 $attempt/3): $error');
        },
      );
    } catch (e) {
      LoggerService.error('📚 查询学期全部开课失败', error: e);
      return ErrorHandler.handleError(e, '查询学期全部开课失败');
    }
  }

  /// 获取单页数据
  Future<CourseScheduleResponse?> _fetchPage({
    required String url,
    required String termCode,
    required int pageNum,
    required int pageSize,
  }) async {
    try {
      final formData = {
        'zxjxjhh': termCode,
        'kkxsh': '',
        'kkxqh': '',
        'jxlh': '',
        'jash': '',
        'skxq': '',
        'skjc': '',
        'kch': '',
        'kcm': '',
        'kclb': '',
        'skjs': '',
        'xqname': '',
        'jcname': '',
        'jxlname': '',
        'jasname': '',
        'pageNum': pageNum.toString(),
        'pageSize': pageSize.toString(),
      };

      final response = await connection.client.post(
        url,
        data: formData,
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      var data = response.data;
      if (data == null) return null;

      if (data is String) {
        data = jsonDecode(data);
      }

      if (data is! Map<String, dynamic>) return null;

      return CourseScheduleResponse.fromJson(data);
    } catch (e) {
      LoggerService.error('📚 获取第 $pageNum 页失败', error: e);
      return null;
    }
  }

  /// 执行并发查询学期全部开课
  Future<UniResponse<List<CourseScheduleRecord>>> _performQueryAllCoursesForTermConcurrent(
    String termCode, {
    void Function(int completed, int total, int records)? onProgress,
  }) async {
    try {
      final url = config.toFullUrl(endpoints['courseInfo']!);
      LoggerService.info('📚 正在并发查询学期全部开课: 学期: $termCode');

      const int pageSize = 200; // 使用更大的页面大小
      const int concurrency = 5; // 并发数

      // 第一步：获取第一页以确定总数
      final firstPage = await _fetchPage(
        url: url,
        termCode: termCode,
        pageNum: 1,
        pageSize: pageSize,
      );

      if (firstPage == null) {
        throw Exception('获取第一页数据失败');
      }

      final totalCount = firstPage.list.pageContext.totalCount;
      final totalPages = (totalCount / pageSize).ceil();
      final allRecords = <CourseScheduleRecord>[...firstPage.list.records];

      LoggerService.info('📚 总共 $totalCount 条记录，$totalPages 页，开始并发获取...');
      onProgress?.call(1, totalPages, allRecords.length);

      if (totalPages <= 1) {
        return UniResponse.success(
          allRecords,
          message: '查询成功，共 ${allRecords.length} 条记录',
        );
      }

      // 第二步：并发获取剩余页面
      int completedPages = 1;
      final remainingPages = List.generate(totalPages - 1, (i) => i + 2);

      // 分批并发请求
      for (int i = 0; i < remainingPages.length; i += concurrency) {
        final batch = remainingPages.skip(i).take(concurrency).toList();
        
        final futures = batch.map((pageNum) => _fetchPage(
          url: url,
          termCode: termCode,
          pageNum: pageNum,
          pageSize: pageSize,
        ));

        final results = await Future.wait(futures);

        for (final result in results) {
          if (result != null) {
            allRecords.addAll(result.list.records);
          }
          completedPages++;
          onProgress?.call(completedPages, totalPages, allRecords.length);
        }

        LoggerService.info(
          '📚 已完成 $completedPages/$totalPages 页，累计 ${allRecords.length} 条',
        );
      }

      LoggerService.info('📚 学期全部开课查询完成，共获取 ${allRecords.length} 条记录');
      return UniResponse.success(
        allRecords,
        message: '查询成功，共 ${allRecords.length} 条记录',
      );
    } on DioException catch (e) {
      LoggerService.error('📚 网络请求失败', error: e);
      rethrow;
    } catch (e) {
      LoggerService.error('📚 解析响应数据失败', error: e);
      rethrow;
    }
  }

  /// 查询课程开课情况（获取全部数据）
  ///
  /// 自动处理分页，获取所有符合条件的记录
  ///
  /// [courseCode] 课程号
  /// [termCode] 学期代码，如 "2025-2026-2-1"
  ///
  /// 成功时返回 UniResponse.success，包含 List<CourseScheduleRecord> 数据
  /// 失败时返回 UniResponse.failure，根据错误类型设置 retryable 标志
  Future<UniResponse<List<CourseScheduleRecord>>> queryCourseScheduleAll({
    required String courseCode,
    required String termCode,
  }) async {
    try {
      return await RetryHandler.retry(
        operation: () async => await _performQueryCourseScheduleAll(
          courseCode: courseCode,
          termCode: termCode,
        ),
        retryIf: RetryHandler.shouldRetryOnError,
        maxAttempts: 3,
        onRetry: (attempt, error) {
          LoggerService.warning('📚 查询课程开课情况失败，正在重试 (尝试 $attempt/3): $error');
        },
      );
    } catch (e) {
      LoggerService.error('📚 查询课程开课情况失败', error: e);
      return ErrorHandler.handleError(e, '查询课程开课情况失败');
    }
  }

  /// 执行查询课程开课情况的实际操作（获取全部数据）
  Future<UniResponse<List<CourseScheduleRecord>>>
      _performQueryCourseScheduleAll({
    required String courseCode,
    required String termCode,
  }) async {
    try {
      final url = config.toFullUrl(endpoints['courseInfo']!);
      LoggerService.info(
        '📚 正在查询课程开课情况(全部): 课程号: $courseCode, 学期: $termCode',
      );

      final allRecords = <CourseScheduleRecord>[];
      int pageNum = 1;
      const int pageSize = 50;
      int totalCount = 0;

      // 循环获取所有分页数据
      while (true) {
        final formData = {
          'zxjxjhh': termCode,
          'kkxsh': '',
          'kkxqh': '',
          'jxlh': '',
          'jash': '',
          'skxq': '',
          'skjc': '',
          'kch': courseCode,
          'kcm': '',
          'kclb': '',
          'skjs': '',
          'xqname': '',
          'jcname': '',
          'jxlname': '',
          'jasname': '',
          'pageNum': pageNum.toString(),
          'pageSize': pageSize.toString(),
        };

        final response = await connection.client.post(
          url,
          data: formData,
          options: Options(contentType: Headers.formUrlEncodedContentType),
        );

        var data = response.data;
        if (data == null) {
          break;
        }

        if (data is String) {
          try {
            data = jsonDecode(data);
          } catch (e) {
            break;
          }
        }

        if (data is! Map<String, dynamic>) {
          break;
        }

        final courseResponse = CourseScheduleResponse.fromJson(data);
        final records = courseResponse.list.records;
        totalCount = courseResponse.list.pageContext.totalCount;

        allRecords.addAll(records);

        LoggerService.info(
          '📚 获取第 $pageNum 页，本页 ${records.length} 条，累计 ${allRecords.length}/$totalCount 条',
        );

        // 如果已获取全部数据或本页为空，退出循环
        if (allRecords.length >= totalCount || records.isEmpty) {
          break;
        }

        pageNum++;
      }

      LoggerService.info('📚 课程开课查询完成，共获取 ${allRecords.length} 条记录');
      return UniResponse.success(
        allRecords,
        message: '查询成功，共 ${allRecords.length} 条记录',
      );
    } on DioException catch (e) {
      LoggerService.error('📚 网络请求失败', error: e);
      rethrow;
    } catch (e) {
      LoggerService.error('📚 解析响应数据失败', error: e);
      rethrow;
    }
  }
}
