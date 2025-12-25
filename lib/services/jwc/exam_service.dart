import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;
import '../../models/backend/uni_response.dart';
import '../../models/jwc/exam_info.dart';
import '../../models/jwc/exam_info_response.dart';
import '../../models/jwc/exam_schedule_item.dart';
import '../../models/jwc/other_exam_record.dart';
import '../../models/jwc/other_exam_response.dart';
import '../../models/jwc/seat_info.dart';
import '../../utils/error_handler.dart';
import '../../utils/retry_handler.dart';
import '../aufe/connector.dart';
import '../logger_service.dart';
import 'academic_service.dart';
import 'jwc_config.dart';

/// 考试信息服务
///
/// 提供考试信息查询功能，包括校统考和其他考试
class ExamService {
  final AUFEConnection connection;
  final JWCConfig config;
  final AcademicService academicService;

  /// API 端点常量
  static const Map<String, String> endpoints = {
    'schoolExamPreRequest': '/student/examinationManagement/examPlan/index',
    'schoolExamRequest': '/student/examinationManagement/examPlan/detail',
    'seatInfo': '/student/examinationManagement/examPlan/index',
    'otherExamRecord':
        '/student/examinationManagement/othersExamPlan/queryScores?sf_request_type=ajax',
  };

  ExamService(this.connection, this.config, this.academicService);

  /// 获取校统考考试安排
  ///
  /// [startDate] 开始日期 (YYYY-MM-DD)
  /// [endDate] 结束日期 (YYYY-MM-DD)
  ///
  /// 返回校统考考试日程列表
  Future<List<ExamScheduleItem>> _fetchSchoolExamSchedule(
    String startDate,
    String endDate,
  ) async {
    try {
      // 先发送预请求
      final preRequestUrl = config.toFullUrl(
        endpoints['schoolExamPreRequest']!,
      );
      LoggerService.info('📝 正在发送校统考预请求: $preRequestUrl');

      await connection.client.get(preRequestUrl);

      // 发送实际请求获取考试数据
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final requestUrl = config.toFullUrl(endpoints['schoolExamRequest']!);
      final fullUrl = '$requestUrl?start=$startDate&end=$endDate&_=$timestamp';

      LoggerService.info('📝 正在获取校统考信息: $fullUrl');

      // 添加 Accept 头确保服务器返回正确编码的数据
      final response = await connection.client.get(
        fullUrl,
        options: Options(
          headers: {
            'Accept': 'application/json, text/javascript, */*; q=0.01',
            'Accept-Charset': 'utf-8',
            'X-Requested-With': 'XMLHttpRequest',
          },
        ),
      );

      // 解析响应数据
      var data = response.data;
      if (data == null) {
        LoggerService.info('📝 校统考响应数据为空');
        return [];
      }

      // 如果响应是字符串，需要手动解析JSON
      if (data is String) {
        // 处理空响应情况（"]" 字符串）
        if (data.trim() == ']') {
          LoggerService.info('📝 校统考数据为空（收到空数组标记）');
          return [];
        }

        try {
          data = jsonDecode(data);
        } catch (e) {
          throw Exception('JSON解析失败: $e');
        }
      }

      // 检查是否为空数组
      if (data is List && data.isEmpty) {
        LoggerService.info('📝 校统考数据为空');
        return [];
      }

      // 解析为 ExamScheduleItem 列表
      if (data is! List) {
        throw Exception('响应数据格式错误：期望数组格式，实际类型: ${data.runtimeType}');
      }

      final examList = data
          .map(
            (item) => ExamScheduleItem.fromJson(item as Map<String, dynamic>),
          )
          .toList();

      LoggerService.info('🎓 获取校统考信息成功，共 ${examList.length} 场考试');
      return examList;
    } catch (e) {
      LoggerService.error('❌ 获取校统考信息失败（网络错误）', error: e);
      rethrow;
    }
  }

  /// 获取考试座位信息
  ///
  /// 从 HTML 页面解析座位信息
  ///
  /// 返回座位信息列表
  Future<List<SeatInfo>> _fetchExamSeatInfo() async {
    try {
      final url = config.toFullUrl(endpoints['seatInfo']!);
      LoggerService.info('🪑 正在获取座位信息: $url');

      // 添加 Accept 头确保服务器返回正确编码的数据
      final response = await connection.client.get(
        url,
        options: Options(
          headers: {
            'Accept': 'text/html, application/xhtml+xml, */*; q=0.01',
            'Accept-Charset': 'utf-8',
          },
        ),
      );

      // 获取 HTML 内容
      var htmlContent = response.data;
      if (htmlContent == null) {
        LoggerService.info('🪑 座位信息响应为空');
        return [];
      }

      // 如果不是字符串，尝试转换
      if (htmlContent is! String) {
        htmlContent = htmlContent.toString();
      }

      // 解析 HTML
      final document = html_parser.parse(htmlContent);
      final seatInfoList = <SeatInfo>[];

      // 查找所有 class="widget-box" 的 div 元素
      final widgetBoxes = document.querySelectorAll('div.widget-box');

      for (final box in widgetBoxes) {
        try {
          // 从 h5.widget-title 提取课程名
          final titleElement = box.querySelector('h5.widget-title');
          if (titleElement == null) continue;

          var courseTitle = titleElement.text.trim();

          // 处理"（课程代码-班号）课程名"格式
          // 例如: "（0301001-01）大学英语（一）"
          final courseNameMatch = RegExp(r'[）)](.+)$').firstMatch(courseTitle);
          final courseName = courseNameMatch?.group(1)?.trim() ?? courseTitle;

          // 从 div.widget-main 提取座位号
          final mainElement = box.querySelector('div.widget-main');
          if (mainElement == null) continue;

          final mainText = mainElement.text.trim();

          // 处理"座位号:"和"座位号："两种格式
          final seatMatch = RegExp(
            r'座位号[：:](.+?)(?:准考证号|$)',
          ).firstMatch(mainText);

          if (seatMatch != null) {
            final seatNumber = seatMatch.group(1)?.trim() ?? '';
            if (seatNumber.isNotEmpty) {
              seatInfoList.add(
                SeatInfo(courseName: courseName, seatNumber: seatNumber),
              );
            }
          }
        } catch (e) {
          LoggerService.warning('⚠️ 解析单个座位信息失败: $e');
          continue;
        }
      }

      LoggerService.info('✅ 获取座位信息成功，共 ${seatInfoList.length} 条记录');
      return seatInfoList;
    } catch (e) {
      LoggerService.error('❌ 获取座位信息失败（网络错误）', error: e);
      rethrow;
    }
  }

  /// 获取其他考试记录
  ///
  /// [termCode] 学期代码
  ///
  /// 返回其他考试记录列表
  Future<List<OtherExamRecord>> _fetchOtherExamRecords(String termCode) async {
    try {
      final url = config.toFullUrl(endpoints['otherExamRecord']!);
      LoggerService.info('📋 正在获取其他考试信息: $url');

      // 构造请求参数（URL 编码格式）
      final formData = 'zxjxjhh=$termCode&tab=0&pageNum=1&pageSize=30';

      // 添加 Accept 头确保服务器返回正确编码的数据
      final response = await connection.client.post(
        url,
        data: formData,
        options: Options(
          contentType: 'application/x-www-form-urlencoded; charset=UTF-8',
          headers: {
            'Accept': 'application/json, text/javascript, */*; q=0.01',
            'Accept-Charset': 'utf-8',
            'X-Requested-With': 'XMLHttpRequest',
          },
        ),
      );

      // 解析响应数据
      var data = response.data;
      if (data == null) {
        LoggerService.info('📋 其他考试响应数据为空');
        return [];
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

      // 解析为 OtherExamResponse
      final examResponse = OtherExamResponse.fromJson(data);

      // 提取 records 字段
      final records = examResponse.records ?? [];

      LoggerService.info('✅ 获取其他考试信息成功，共 ${records.length} 条记录');
      return records;
    } catch (e) {
      LoggerService.error('❌ 获取其他考试信息失败（网络错误）', error: e);
      rethrow;
    }
  }

  /// 将校统考数据转换为统一格式
  ///
  /// [exam] 校统考日程项
  /// [seatInfos] 座位信息列表
  ///
  /// 返回统一格式的考试信息，如果解析失败返回 null
  UnifiedExamInfo? _convertSchoolExamToUnified(
    ExamScheduleItem exam,
    List<SeatInfo> seatInfos,
  ) {
    try {
      // 解析 title 字段（按 \n 分割）
      final lines = exam.title.split('\n').map((e) => e.trim()).toList();

      if (lines.isEmpty) {
        LoggerService.warning('⚠️ 校统考数据格式错误：title 为空');
        return null;
      }

      // 提取课程名（第一行）
      final courseName = lines[0];

      // 提取考试时间（第二行）
      String examTime = '';
      if (lines.length > 1) {
        examTime = lines[1];
      }

      // 提取考试地点（后续行拼接）
      String examLocation = '';
      if (lines.length > 2) {
        examLocation = lines.sublist(2).join(' ').trim();
      }

      // 匹配座位信息
      String note = '';
      for (final seatInfo in seatInfos) {
        if (seatInfo.courseName == courseName) {
          note = '座位号: ${seatInfo.seatNumber}';
          break;
        }
      }

      // 移除 note 中的"准考证号："后缀
      note = note.replaceAll(RegExp(r'准考证号[：:].*$'), '').trim();

      return UnifiedExamInfo(
        courseName: courseName,
        examDate: exam.start,
        examTime: examTime,
        examLocation: examLocation,
        examType: '校统考',
        note: note,
      );
    } catch (e) {
      LoggerService.error('❌ 转换校统考数据失败', error: e);
      return null;
    }
  }

  /// 将中文日期格式转换为标准格式
  ///
  /// 例如: "2026年1月3日" -> "2026-01-03"
  String _convertChineseDateToStandard(String chineseDate) {
    try {
      // 匹配 "2026年1月3日" 格式
      final match = RegExp(r'(\d{4})年(\d{1,2})月(\d{1,2})日').firstMatch(chineseDate);
      if (match != null) {
        final year = match.group(1)!;
        final month = match.group(2)!.padLeft(2, '0');
        final day = match.group(3)!.padLeft(2, '0');
        return '$year-$month-$day';
      }
      // 如果不匹配，返回原始值
      return chineseDate;
    } catch (e) {
      LoggerService.warning('⚠️ 日期格式转换失败: $chineseDate');
      return chineseDate;
    }
  }

  /// 将其他考试记录转换为统一格式
  ///
  /// [record] 其他考试记录
  ///
  /// 返回统一格式的考试信息，如果解析失败返回 null
  UnifiedExamInfo? _convertOtherExamToUnified(OtherExamRecord record) {
    try {
      // 转换中文日期格式为标准格式
      final standardDate = _convertChineseDateToStandard(record.examDate);
      
      return UnifiedExamInfo(
        courseName: record.courseName,
        examDate: standardDate,
        examTime: record.examTime,
        examLocation: record.examLocation,
        examType: '其他考试',
        note: record.note,
      );
    } catch (e) {
      LoggerService.error('❌ 转换其他考试数据失败', error: e);
      return null;
    }
  }

  /// 聚合考试信息
  ///
  /// [startDate] 开始日期 (YYYY-MM-DD)
  /// [endDate] 结束日期 (YYYY-MM-DD)
  /// [termCode] 学期代码
  ///
  /// 返回聚合后的考试信息响应
  Future<ExamInfoResponse> _aggregateExamInfo(
    String startDate,
    String endDate,
    String termCode,
  ) async {
    try {
      LoggerService.info('📊 开始聚合考试信息');

      // 并行获取校统考和其他考试信息
      final results = await Future.wait([
        _fetchSchoolExamSchedule(startDate, endDate),
        _fetchOtherExamRecords(termCode),
      ]);

      final schoolExams = results[0] as List<ExamScheduleItem>;
      final otherExams = results[1] as List<OtherExamRecord>;

      // 获取座位信息
      final seatInfos = await _fetchExamSeatInfo();

      // 转换校统考数据为统一格式
      final unifiedSchoolExams = schoolExams
          .map((exam) => _convertSchoolExamToUnified(exam, seatInfos))
          .where((exam) => exam != null)
          .cast<UnifiedExamInfo>()
          .toList();

      // 转换其他考试数据为统一格式
      final unifiedOtherExams = otherExams
          .map((record) => _convertOtherExamToUnified(record))
          .where((exam) => exam != null)
          .cast<UnifiedExamInfo>()
          .toList();

      // 合并两个列表
      final allExams = [...unifiedSchoolExams, ...unifiedOtherExams];

      // 按 examDate + examTime 排序
      allExams.sort((a, b) {
        final dateCompare = a.examDate.compareTo(b.examDate);
        if (dateCompare != 0) return dateCompare;
        return a.examTime.compareTo(b.examTime);
      });

      LoggerService.info('📊 考试信息聚合完成，共 ${allExams.length} 场考试');

      return ExamInfoResponse(exams: allExams, totalCount: allExams.length);
    } catch (e) {
      LoggerService.error('❌ 聚合考试信息失败', error: e);
      rethrow;
    }
  }

  /// 获取考试信息（公共 API）
  ///
  /// 自动获取当前学期信息并计算日期范围
  /// 聚合校统考和其他考试信息
  ///
  /// 成功时返回 UniResponse.success，包含 ExamInfoResponse 数据
  /// 失败时返回 UniResponse.failure，根据错误类型设置 retryable 标志
  Future<UniResponse<ExamInfoResponse>> getExamInfo() async {
    try {
      return await RetryHandler.retry(
        operation: () async => await _performGetExamInfo(),
        retryIf: RetryHandler.shouldRetryOnError,
        maxAttempts: 3,
        onRetry: (attempt, error) {
          LoggerService.warning('📝 获取考试信息失败，正在重试 (尝试 $attempt/3): $error');
        },
      );
    } catch (e) {
      LoggerService.error('📝 获取考试信息失败', error: e);
      return ErrorHandler.handleError(e, '获取考试信息失败');
    }
  }

  /// 执行获取考试信息的实际操作
  Future<UniResponse<ExamInfoResponse>> _performGetExamInfo() async {
    try {
      LoggerService.info('📝 开始获取考试信息');

      // 首先获取当前学期代码
      final academicResponse = await academicService.getAcademicInfo();
      if (!academicResponse.success || academicResponse.data == null) {
        throw Exception('无法获取学期信息: ${academicResponse.error}');
      }

      final termCode = academicResponse.data!.currentTerm;
      LoggerService.info('📝 当前学期代码: $termCode');

      // 根据学期代码计算日期范围
      final now = DateTime.now();
      final startDate =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      String endDate;
      // 判断学期类型（秋季学期：末尾为1，春季学期：末尾为2）
      if (termCode.endsWith('1')) {
        // 秋季学期：到次年3月30日
        final nextYear = now.year + 1;
        endDate = '$nextYear-03-30';
      } else {
        // 春季学期：到当年9月30日
        endDate = '${now.year}-09-30';
      }

      LoggerService.info('📝 查询日期范围: $startDate 至 $endDate');

      // 调用聚合方法获取考试信息
      final examInfoResponse = await _aggregateExamInfo(
        startDate,
        endDate,
        termCode,
      );

      LoggerService.info('📝 考试信息获取成功');
      return UniResponse.success(examInfoResponse, message: '考试信息获取成功');
    } catch (e) {
      LoggerService.error('📝 网络请求失败', error: e);
      rethrow;
    }
  }
}
