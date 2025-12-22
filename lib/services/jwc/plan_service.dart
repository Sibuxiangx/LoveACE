import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;

import '../../models/backend/uni_response.dart';
import '../../models/jwc/plan_completion_info.dart';
import '../../models/jwc/plan_category.dart';
import '../../models/jwc/plan_course.dart';
import '../../models/jwc/plan_option.dart';
import '../../models/jwc/score_record.dart';
import '../../utils/error_handler.dart';
import '../../utils/retry_handler.dart';
import '../aufe/connector.dart';
import '../logger_service.dart';
import 'jwc_config.dart';
import 'score_service.dart';
import 'term_service.dart';

/// 培养方案完成情况服务
///
/// 提供培养方案完成情况的查询功能
/// 当检测到所有课程未通过时，会自动拉取学期成绩进行匹配
/// 内置请求锁和节流机制，防止频繁请求导致封禁
class PlanService {
  final AUFEConnection connection;
  final JWCConfig config;

  /// 学期服务（用于获取学期列表）
  late final TermService _termService;

  /// 成绩服务（用于获取学期成绩）
  late final ScoreService _scoreService;

  /// 请求锁 - 防止并发请求
  bool _isRequesting = false;

  /// 上次请求时间
  DateTime? _lastRequestTime;

  /// 最小请求间隔（秒）
  static const int _minRequestIntervalSeconds = 3;

  /// 缓存的培养方案数据（按 planId 缓存）
  final Map<String?, PlanCompletionInfo> _planCache = {};

  /// 缓存的培养方案选项
  PlanSelectionResponse? _planOptionsCache;

  /// 缓存有效期（分钟）
  static const int _cacheValidMinutes = 5;

  /// 缓存时间戳
  final Map<String?, DateTime> _cacheTimestamps = {};

  /// API端点常量
  static const Map<String, String> endpoints = {
    'plan': '/student/integratedQuery/planCompletion/index',
    'planByFajhh': '/student/integratedQuery/planCompletion/getPyfaIndex/',
  };

  PlanService(this.connection, this.config) {
    _termService = TermService(connection, config);
    _scoreService = ScoreService(connection, config);
  }

  /// 检查缓存是否有效
  bool _isCacheValid(String? planId) {
    final timestamp = _cacheTimestamps[planId];
    if (timestamp == null) return false;
    return DateTime.now().difference(timestamp).inMinutes < _cacheValidMinutes;
  }

  /// 清除所有缓存
  void clearCache() {
    _planCache.clear();
    _planOptionsCache = null;
    _cacheTimestamps.clear();
    LoggerService.info('🗑️ 培养方案缓存已清除');
  }

  /// 等待请求锁释放
  Future<void> _waitForLock() async {
    int waitCount = 0;
    while (_isRequesting && waitCount < 30) {
      // 最多等待30秒
      await Future.delayed(const Duration(seconds: 1));
      waitCount++;
    }
  }

  /// 检查并等待节流
  Future<void> _throttle() async {
    if (_lastRequestTime != null) {
      final elapsed = DateTime.now().difference(_lastRequestTime!).inSeconds;
      if (elapsed < _minRequestIntervalSeconds) {
        final waitTime = _minRequestIntervalSeconds - elapsed;
        LoggerService.info('⏳ 请求节流，等待 $waitTime 秒...');
        await Future.delayed(Duration(seconds: waitTime));
      }
    }
  }

  /// 获取培养方案完成信息
  ///
  /// 返回包含培养方案完成情况的响应
  /// 使用 compute 隔离进行 HTML 解析以避免阻塞 UI 线程
  /// 内置请求锁和缓存机制，防止频繁请求
  ///
  /// 成功时返回 UniResponse.success，包含 PlanCompletionInfo 数据
  /// 如果用户有多个培养方案需要选择，返回 UniResponse.needSelection
  /// 失败时返回 UniResponse.failure，根据错误类型设置 retryable 标志
  ///
  /// [planId] 可选的培养方案ID，用于多培养方案用户选择具体方案
  /// [forceRefresh] 是否强制刷新（忽略缓存）
  Future<UniResponse<PlanCompletionInfo>> getPlanCompletion({
    String? planId,
    bool forceRefresh = false,
  }) async {
    // 检查缓存（非强制刷新时）
    if (!forceRefresh && _isCacheValid(planId) && _planCache.containsKey(planId)) {
      LoggerService.info('📦 使用缓存的培养方案数据 (planId: $planId)');
      return UniResponse.success(_planCache[planId]!, message: '培养方案获取成功（缓存）');
    }

    // 如果正在请求中，等待锁释放后返回缓存
    if (_isRequesting) {
      LoggerService.warning('🔒 培养方案请求正在进行中，等待...');
      await _waitForLock();
      // 等待后检查缓存
      if (_planCache.containsKey(planId)) {
        return UniResponse.success(_planCache[planId]!, message: '培养方案获取成功（缓存）');
      }
    }

    // 获取锁
    _isRequesting = true;

    try {
      // 节流
      await _throttle();

      final result = await RetryHandler.retry(
        operation: () async => await _performGetPlanCompletion(planId: planId),
        retryIf: RetryHandler.shouldRetryOnError,
        maxAttempts: 3,
        onRetry: (attempt, error) {
          LoggerService.warning('📚 获取培养方案失败，正在重试 (尝试 $attempt/3): $error');
        },
      );

      // 更新请求时间
      _lastRequestTime = DateTime.now();

      // 缓存成功的结果
      if (result.success && result.data != null) {
        _planCache[planId] = result.data!;
        _cacheTimestamps[planId] = DateTime.now();
      }

      return result;
    } catch (e) {
      LoggerService.error('📚 获取培养方案失败', error: e);
      return ErrorHandler.handleError(e, '获取培养方案失败');
    } finally {
      // 释放锁
      _isRequesting = false;
    }
  }

  /// 获取培养方案选项列表（用于多培养方案用户）
  ///
  /// 返回可选的培养方案列表
  /// 内置缓存机制
  Future<UniResponse<PlanSelectionResponse>> getPlanOptions() async {
    // 检查缓存
    if (_planOptionsCache != null) {
      LoggerService.info('📦 使用缓存的培养方案选项');
      return UniResponse.success(_planOptionsCache!, message: '获取培养方案选项成功（缓存）');
    }

    try {
      return await RetryHandler.retry(
        operation: () async {
          final result = await _performGetPlanOptions();
          // 缓存成功的结果
          if (result.success && result.data != null) {
            _planOptionsCache = result.data;
          }
          return result;
        },
        retryIf: RetryHandler.shouldRetryOnError,
        maxAttempts: 3,
        onRetry: (attempt, error) {
          LoggerService.warning('📚 获取培养方案选项失败，正在重试 (尝试 $attempt/3): $error');
        },
      );
    } catch (e) {
      LoggerService.error('📚 获取培养方案选项失败', error: e);
      return ErrorHandler.handleError(e, '获取培养方案选项失败');
    }
  }

  /// 执行获取培养方案选项的实际操作
  Future<UniResponse<PlanSelectionResponse>> _performGetPlanOptions() async {
    try {
      final url = config.toFullUrl(endpoints['plan']!);
      LoggerService.info('📚 正在获取培养方案选项: $url');

      final response = await connection.client.get(url);

      var data = response.data;
      if (data == null) {
        throw Exception('响应数据为空');
      }

      String htmlContent;
      if (data is String) {
        htmlContent = data;
      } else {
        throw Exception('响应数据格式错误：期望HTML字符串，实际类型: ${data.runtimeType}');
      }

      // 解析培养方案选项
      final selectionResponse = _parsePlanSelectionHtml(htmlContent);
      if (selectionResponse != null) {
        LoggerService.info('📚 检测到多培养方案，共 ${selectionResponse.options.length} 个选项');
        return UniResponse.success(selectionResponse, message: '获取培养方案选项成功');
      }

      // 如果不是选择页面，返回空列表
      return UniResponse.success(
        PlanSelectionResponse(options: [], hint: '无需选择培养方案'),
        message: '无需选择培养方案',
      );
    } catch (e) {
      LoggerService.error('📚 获取培养方案选项失败', error: e);
      rethrow;
    }
  }

  /// 执行获取培养方案的实际操作
  Future<UniResponse<PlanCompletionInfo>> _performGetPlanCompletion({String? planId}) async {
    try {
      String url;
      if (planId != null && planId.isNotEmpty) {
        // 使用指定的培养方案ID
        url = config.toFullUrl('${endpoints['planByFajhh']}$planId');
        LoggerService.info('📚 正在获取指定培养方案: $url');
      } else {
        url = config.toFullUrl(endpoints['plan']!);
        LoggerService.info('📚 正在获取培养方案: $url');
      }

      final response = await connection.client.get(url);

      // 解析响应数据
      var data = response.data;
      if (data == null) {
        throw Exception('响应数据为空');
      }

      // 确保数据是字符串格式（HTML）
      String htmlContent;
      if (data is String) {
        htmlContent = data;
      } else {
        throw Exception('响应数据格式错误：期望HTML字符串，实际类型: ${data.runtimeType}');
      }

      // 首先检查是否是多培养方案选择页面
      final selectionResponse = _parsePlanSelectionHtml(htmlContent);
      if (selectionResponse != null && selectionResponse.options.isNotEmpty) {
        LoggerService.info('📚 检测到多培养方案选择页面，需要用户选择');
        // 返回特殊的响应，表示需要选择培养方案
        return UniResponse<PlanCompletionInfo>.needSelection(
          selectionResponse,
          message: '请选择要查看的培养方案',
        );
      }

      LoggerService.info('📚 开始解析HTML数据...');

      // 在 compute 隔离中解析 HTML
      var planInfo = await compute(_parseHtmlInIsolate, htmlContent);

      // 检查是否所有课程都未通过（可能是数据解析问题）
      if (planInfo.passedCourses == 0 && planInfo.totalCourses > 0) {
        LoggerService.warning('⚠️ 检测到所有课程未通过，尝试从学期成绩中匹配...');
        planInfo = await _enrichWithTermScores(planInfo);
      }

      LoggerService.info('📚 培养方案获取成功');
      return UniResponse.success(planInfo, message: '培养方案获取成功');
    } catch (e) {
      LoggerService.error('📚 网络请求失败', error: e);
      rethrow;
    }
  }

  /// 解析培养方案选择页面的HTML
  ///
  /// 如果是多培养方案选择页面，返回 PlanSelectionResponse
  /// 否则返回 null
  static PlanSelectionResponse? _parsePlanSelectionHtml(String html) {
    try {
      final document = html_parser.parse(html);

      // 查找培养方案选择按钮
      // 格式: <button class="btn btn-success btn-round" onclick="getPyfaIndex('7352');return false;">2024级供应链管理本科培养方案(主修)</button>
      final buttons = document.querySelectorAll('button.btn-success.btn-round');

      if (buttons.isEmpty) {
        return null;
      }

      final options = <PlanOption>[];
      String? hint;

      // 尝试获取提示信息
      final alertDiv = document.querySelector('.alert-warning strong');
      if (alertDiv != null) {
        // 获取完整的提示文本
        final alertContainer = document.querySelector('.alert-warning');
        if (alertContainer != null) {
          hint = alertContainer.text.trim().replaceAll(RegExp(r'\s+'), ' ');
        }
      }

      for (final button in buttons) {
        final onclick = button.attributes['onclick'] ?? '';
        final buttonText = button.text.trim();

        // 解析 onclick 中的方案ID: getPyfaIndex('7352')
        final match = RegExp(r"getPyfaIndex\('(\d+)'\)").firstMatch(onclick);
        if (match != null) {
          final planId = match.group(1)!;

          // 解析方案类型（主修/辅修）
          String planType = '主修';
          if (buttonText.contains('辅修')) {
            planType = '辅修';
          } else if (buttonText.contains('微专业')) {
            planType = '微专业';
          }

          // 判断是否为当前使用的方案（绿色按钮表示当前使用）
          final isCurrent = button.classes.contains('btn-success');

          options.add(PlanOption(
            planId: planId,
            planName: buttonText,
            planType: planType,
            isCurrent: isCurrent,
          ));
        }
      }

      if (options.isEmpty) {
        return null;
      }

      return PlanSelectionResponse(
        options: options,
        hint: hint,
      );
    } catch (e) {
      LoggerService.error('📚 解析培养方案选择页面失败', error: e);
      return null;
    }
  }

  /// 从学期成绩中补充课程通过状态
  ///
  /// 当培养方案中所有课程都显示未通过时，
  /// 通过拉取所有学期成绩来匹配并更新课程状态
  Future<PlanCompletionInfo> _enrichWithTermScores(
    PlanCompletionInfo planInfo,
  ) async {
    try {
      // 1. 获取学期列表
      LoggerService.info('📅 正在获取学期列表...');
      final termResponse = await _termService.getAllTerms();
      if (!termResponse.success || termResponse.data == null) {
        LoggerService.warning('⚠️ 获取学期列表失败，使用原始数据');
        return planInfo;
      }

      final terms = termResponse.data!;
      LoggerService.info('📅 获取到 ${terms.length} 个学期');

      // 2. 批量获取所有学期的成绩（串行，复用动态路径）
      final termCodes = terms.map((t) => t.termCode).toList();
      LoggerService.info('📊 正在批量获取所有学期成绩...');

      final scoresResponse = await _scoreService.getAllTermsScores(termCodes);
      if (!scoresResponse.success || scoresResponse.data == null) {
        LoggerService.warning('⚠️ 批量获取学期成绩失败，使用原始数据');
        return planInfo;
      }

      final allScores = scoresResponse.data!;
      LoggerService.info('📊 共获取到 ${allScores.length} 条成绩记录');

      if (allScores.isEmpty) {
        LoggerService.warning('⚠️ 未获取到任何成绩记录，使用原始数据');
        return planInfo;
      }

      // 3. 构建课程代码到成绩的映射（取最高成绩）
      final scoreMap = <String, ScoreRecord>{};
      for (final score in allScores) {
        final code = score.courseCode;
        if (!scoreMap.containsKey(code)) {
          scoreMap[code] = score;
        } else {
          // 如果已存在，比较成绩取较高的
          final existing = scoreMap[code]!;
          if (_compareScores(score, existing) > 0) {
            scoreMap[code] = score;
          }
        }
      }

      LoggerService.info('📊 构建课程成绩映射，共 ${scoreMap.length} 门课程');

      // 4. 更新培养方案中的课程状态
      final updatedCategories = _updateCategoriesWithScores(
        planInfo.categories,
        scoreMap,
      );

      // 5. 重新计算统计信息
      final updatedPlanInfo = PlanCompletionInfo(
        planName: planInfo.planName,
        major: planInfo.major,
        grade: planInfo.grade,
        categories: updatedCategories,
      ).calculateStatistics();

      LoggerService.info(
        '✅ 成绩匹配完成: 总课程 ${updatedPlanInfo.totalCourses}, '
        '已通过 ${updatedPlanInfo.passedCourses}, '
        '未通过 ${updatedPlanInfo.failedCourses}, '
        '未修读 ${updatedPlanInfo.unreadCourses}',
      );

      return updatedPlanInfo;
    } catch (e) {
      LoggerService.error('❌ 从学期成绩补充数据失败', error: e);
      return planInfo;
    }
  }

  /// 比较两个成绩记录，返回正数表示 a 更好
  int _compareScores(ScoreRecord a, ScoreRecord b) {
    // 获取有效成绩（优先使用重修成绩、补考成绩）
    final scoreA = _getEffectiveScore(a);
    final scoreB = _getEffectiveScore(b);

    // 如果都是数字成绩，比较数值
    final numA = double.tryParse(scoreA);
    final numB = double.tryParse(scoreB);

    if (numA != null && numB != null) {
      return numA.compareTo(numB);
    }

    // 如果有一个是及格/通过，优先选择
    if (_isPassingGrade(scoreA) && !_isPassingGrade(scoreB)) return 1;
    if (!_isPassingGrade(scoreA) && _isPassingGrade(scoreB)) return -1;

    return 0;
  }

  /// 获取有效成绩（优先使用重修成绩、补考成绩）
  String _getEffectiveScore(ScoreRecord record) {
    // 优先使用重修成绩
    if (record.retakeScore != null && record.retakeScore!.isNotEmpty) {
      return record.retakeScore!;
    }
    // 其次使用补考成绩
    if (record.makeupScore != null && record.makeupScore!.isNotEmpty) {
      return record.makeupScore!;
    }
    // 最后使用原始成绩
    return record.score;
  }

  /// 判断成绩是否及格
  bool _isPassingGrade(String score) {
    // 数字成绩 >= 60 及格
    final num = double.tryParse(score);
    if (num != null) {
      return num >= 60;
    }

    // 等级成绩
    final passingGrades = ['优秀', '良好', '中等', '及格', '合格', '通过', 'A', 'B', 'C', 'D'];
    return passingGrades.any(
      (g) => score.toUpperCase().contains(g.toUpperCase()),
    );
  }

  /// 递归更新分类中的课程状态
  List<PlanCategory> _updateCategoriesWithScores(
    List<PlanCategory> categories,
    Map<String, ScoreRecord> scoreMap,
  ) {
    return categories.map((category) {
      // 更新课程
      final updatedCourses = category.courses.map((course) {
        final scoreRecord = scoreMap[course.courseCode];
        if (scoreRecord != null) {
          final effectiveScore = _getEffectiveScore(scoreRecord);
          final isPassed = _isPassingGrade(effectiveScore);

          return PlanCourse(
            courseCode: course.courseCode,
            courseName: course.courseName,
            credits: course.credits ?? double.tryParse(scoreRecord.credits),
            score: effectiveScore,
            examDate: course.examDate,
            courseType: course.courseType,
            isPassed: isPassed,
            statusDescription: isPassed ? '已通过' : '未通过',
          );
        }
        return course;
      }).toList();

      // 递归更新子分类
      final updatedSubcategories = _updateCategoriesWithScores(
        category.subcategories,
        scoreMap,
      );

      // 重新计算分类统计
      int passedCourses = 0;
      int failedCourses = 0;
      double completedCredits = 0.0;

      for (final course in updatedCourses) {
        if (course.isPassed) {
          passedCourses++;
          completedCredits += course.credits ?? 0;
        } else if (course.statusDescription == '未通过') {
          failedCourses++;
        }
      }

      // 加上子分类的统计
      for (final sub in updatedSubcategories) {
        passedCourses += sub.passedCourses;
        failedCourses += sub.failedCourses;
        completedCredits += sub.completedCredits;
      }

      return PlanCategory(
        categoryId: category.categoryId,
        categoryName: category.categoryName,
        minCredits: category.minCredits,
        completedCredits: completedCredits,
        totalCourses: updatedCourses.length,
        passedCourses: passedCourses,
        failedCourses: failedCourses,
        missingRequiredCourses: category.missingRequiredCourses,
        subcategories: updatedSubcategories,
        courses: updatedCourses,
      );
    }).toList();
  }

  /// 在 compute 中执行的 HTML 解析函数
  ///
  /// 参数：HTML 字符串
  /// 返回：解析后的 PlanCompletionInfo 对象
  static Future<PlanCompletionInfo> _parseHtmlInIsolate(String html) async {
    try {
      // 解析 HTML 文档
      final document = html_parser.parse(html);

      // 提取培养方案名称、专业、年级
      String planName = '';
      String major = '';
      String grade = '';

      // 方法1: 从 h4.widget-title 中提取（最准确）
      final h4Elements = document.querySelectorAll('h4.widget-title');
      for (var element in h4Elements) {
        final text = element.text.trim();
        if (text.contains('培养方案')) {
          planName = text;
          // 提取年级和专业：如 "2024级网络与新媒体本科培养方案"
          final planMatch = RegExp(r'(\d{4})级(.+?)本科培养方案').firstMatch(text);
          if (planMatch != null) {
            grade = planMatch.group(1) ?? '';
            major = planMatch.group(2) ?? '';
          }
          break;
        }
      }

      // 方法2: 如果h4中没找到，尝试从页面标题中提取
      if (planName.isEmpty) {
        final titleElement = document.querySelector('title');
        if (titleElement != null) {
          final titleText = titleElement.text.trim();
          if (titleText.contains('培养方案') || titleText == '方案完成情况') {
            // 如果标题是"方案完成情况"，尝试从其他地方找
            final contentElements = document.querySelectorAll(
              'h1, h2, h3, h4, .title',
            );
            for (var element in contentElements) {
              final text = element.text.trim();
              if (text.contains('级') && text.contains('培养方案')) {
                planName = text;
                final planMatch = RegExp(
                  r'(\d{4})级(.+?)本科培养方案',
                ).firstMatch(text);
                if (planMatch != null) {
                  grade = planMatch.group(1) ?? '';
                  major = planMatch.group(2) ?? '';
                }
                break;
              }
            }
          } else {
            // 标题本身包含培养方案信息
            planName = titleText;
            final planMatch = RegExp(
              r'(\d{4})级(.+?)本科培养方案',
            ).firstMatch(titleText);
            if (planMatch != null) {
              grade = planMatch.group(1) ?? '';
              major = planMatch.group(2) ?? '';
            }
          }
        }
      }

      // 从 script 标签中提取 zTree 数据
      List<Map<String, dynamic>> ztreeNodes = [];

      final scriptElements = document.querySelectorAll('script');

      // 尝试多种模式匹配
      final patterns = [
        // 模式1: $.fn.zTree.init($("#treeDemo"), setting, [...]);
        RegExp(
          r'\$\.fn\.zTree\.init\s*\(\s*\$\(\s*["'
          "'"
          r']#treeDemo["'
          "'"
          r']\s*\)\s*,\s*\w+\s*,\s*(\[[\s\S]*?\])\s*\)',
          multiLine: true,
        ),
        // 模式2: .zTree.init(..., ..., [...]);
        RegExp(
          r'\.zTree\.init\s*\([^,]+,\s*[^,]+,\s*(\[[\s\S]*?\])\s*\)',
          multiLine: true,
        ),
        // 模式3: init($("#treeDemo")..., ..., [...])
        RegExp(
          r'init\s*\(\s*\$\(\s*["'
          "'"
          r']#treeDemo["'
          "'"
          r']\s*\)[^,]*,\s*[^,]*,\s*(\[[\s\S]*?\])',
          multiLine: true,
        ),
      ];

      bool foundData = false;

      for (var script in scriptElements) {
        final scriptContent = script.text;

        // 检查是否包含 zTree 初始化代码
        if (!scriptContent.contains('zTree.init') ||
            !scriptContent.contains('flagId')) {
          continue;
        }

        // 尝试所有模式
        for (var pattern in patterns) {
          final match = pattern.firstMatch(scriptContent);
          if (match != null) {
            var jsonString = match.group(1)!;

            // 清理 JSON 字符串
            // 1. 移除 JavaScript 单行注释
            jsonString = jsonString.replaceAll(
              RegExp(r'//.*?$', multiLine: true),
              '',
            );

            // 2. 移除 JavaScript 多行注释
            jsonString = jsonString.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');

            // 3. 移除对象或数组末尾的多余逗号
            jsonString = jsonString.replaceAll(RegExp(r',(\s*[}\]])'), r'$1');

            // 4. 规范化空白字符
            jsonString = jsonString.replaceAll(RegExp(r'\s+'), ' ').trim();

            try {
              // 解析 JSON
              final parsed = jsonDecode(jsonString);
              if (parsed is List && parsed.isNotEmpty) {
                ztreeNodes = parsed.map((node) {
                  if (node is Map<String, dynamic>) {
                    return node;
                  } else {
                    return <String, dynamic>{};
                  }
                }).toList();
                foundData = true;
                break;
              }
            } catch (e) {
              // JSON 解析失败，尝试下一个模式
              continue;
            }
          }
        }

        if (foundData) {
          break;
        }
      }

      if (ztreeNodes.isEmpty) {
        // 提供更详细的错误信息
        final containsZTree = html.contains('zTree');
        final containsFlagId = html.contains('flagId');
        final containsPlan = html.contains('培养方案');

        final debugInfo =
            'HTML长度: ${html.length}, '
            '包含zTree: $containsZTree, '
            '包含flagId: $containsFlagId, '
            '包含培养方案: $containsPlan';

        if (containsPlan && !containsZTree) {
          throw Exception('检测到培养方案内容，但zTree数据解析失败，可能页面结构已变化。$debugInfo');
        } else if (!containsPlan) {
          throw Exception('未检测到培养方案相关内容，可能需要重新登录或检查访问权限。$debugInfo');
        } else {
          throw Exception('未找到有效的zTree数据。$debugInfo');
        }
      }

      // 构建分类树（将在下一个子任务中实现）
      final categories = _buildCategoryTree(ztreeNodes);

      // 创建 PlanCompletionInfo 对象
      final planInfo = PlanCompletionInfo(
        planName: planName.isNotEmpty ? planName : '培养方案',
        major: major.isNotEmpty ? major : '未知专业',
        grade: grade.isNotEmpty ? grade : '未知年级',
        categories: categories,
      );

      // 计算统计信息
      return planInfo.calculateStatistics();
    } catch (e) {
      throw Exception('HTML解析失败: $e');
    }
  }

  /// 构建分类树
  ///
  /// 从 zTree 节点列表构建多层级分类树结构
  static List<PlanCategory> _buildCategoryTree(
    List<Map<String, dynamic>> nodes,
  ) {
    // 创建节点映射，按 ID 索引所有节点
    final Map<String, Map<String, dynamic>> nodesById = {};
    for (var node in nodes) {
      final id = node['id']?.toString() ?? '';
      if (id.isNotEmpty) {
        nodesById[id] = node;
      }
    }

    // 识别真正的根节点（pId 为 "-1"）
    final List<PlanCategory> rootCategories = [];

    for (var node in nodes) {
      final pId = node['pId']?.toString() ?? '';
      // 只处理 pId 为 "-1" 的根节点
      if (pId == '-1') {
        final flagType = node['flagType']?.toString() ?? '';

        // 只处理分类节点，跳过课程节点
        if (flagType != 'kch') {
          // 递归构建包含所有子项的分类（会自动处理所有层级）
          final category = _buildCategoryWithChildren(node, nodesById);
          rootCategories.add(category);
        }
      }
    }

    return rootCategories;
  }

  /// 从单个节点构建分类对象（包含所有子项）
  ///
  /// 递归构建子分类和课程，支持任意层级的嵌套
  static PlanCategory _buildCategoryWithChildren(
    Map<String, dynamic> node,
    Map<String, Map<String, dynamic>> nodesById,
  ) {
    final category = PlanCategory.fromZTreeNode(node);
    final categoryId = node['id']?.toString() ?? '';

    final List<PlanCategory> subcategories = [];
    final List<PlanCourse> courses = [];

    // 遍历所有节点，找到父节点是当前分类的直接子节点
    for (var childNode in nodesById.values) {
      final childPId = childNode['pId']?.toString() ?? '';

      // 只处理直接子节点（pId 等于当前节点的 id）
      if (childPId == categoryId) {
        final childFlagType = childNode['flagType']?.toString() ?? '';
        final childId = childNode['id']?.toString() ?? '';

        // 判断是分类还是课程
        if (childFlagType == 'kch') {
          // 明确标记为课程
          final course = PlanCourse.fromZTreeNode(childNode);
          courses.add(course);
        } else if (childFlagType == '001' || childFlagType == '002') {
          // 明确标记为分类或子分类 - 递归构建（支持多层嵌套）
          final subcategory = _buildCategoryWithChildren(childNode, nodesById);
          subcategories.add(subcategory);
        } else {
          // flagType 未知或为空，根据是否有子节点判断
          final hasChildren = nodesById.values.any(
            (n) => n['pId']?.toString() == childId,
          );

          if (hasChildren) {
            // 有子节点，当作分类处理 - 递归构建（支持多层嵌套）
            final subcategory = _buildCategoryWithChildren(
              childNode,
              nodesById,
            );
            subcategories.add(subcategory);
          } else {
            // 无子节点，当作课程处理
            final course = PlanCourse.fromZTreeNode(childNode);
            courses.add(course);
          }
        }
      }
    }

    // 返回包含所有子项的新分类对象
    return PlanCategory(
      categoryId: category.categoryId,
      categoryName: category.categoryName,
      minCredits: category.minCredits,
      completedCredits: category.completedCredits,
      totalCourses: category.totalCourses,
      passedCourses: category.passedCourses,
      failedCourses: category.failedCourses,
      missingRequiredCourses: category.missingRequiredCourses,
      subcategories: subcategories,
      courses: courses,
    );
  }
}
