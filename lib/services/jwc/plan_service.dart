import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;

import '../../models/backend/uni_response.dart';
import '../../models/jwc/plan_completion_info.dart';
import '../../models/jwc/plan_category.dart';
import '../../models/jwc/plan_course.dart';
import '../../utils/error_handler.dart';
import '../../utils/retry_handler.dart';
import '../aufe/connector.dart';
import '../logger_service.dart';
import 'jwc_config.dart';

/// 培养方案完成情况服务
///
/// 提供培养方案完成情况的查询功能
class PlanService {
  final AUFEConnection connection;
  final JWCConfig config;

  /// API端点常量
  static const Map<String, String> endpoints = {
    'plan': '/student/integratedQuery/planCompletion/index',
  };

  PlanService(this.connection, this.config);

  /// 获取培养方案完成信息
  ///
  /// 返回包含培养方案完成情况的响应
  /// 使用 compute 隔离进行 HTML 解析以避免阻塞 UI 线程
  ///
  /// 成功时返回 UniResponse.success，包含 PlanCompletionInfo 数据
  /// 失败时返回 UniResponse.failure，根据错误类型设置 retryable 标志
  Future<UniResponse<PlanCompletionInfo>> getPlanCompletion() async {
    try {
      return await RetryHandler.retry(
        operation: () async => await _performGetPlanCompletion(),
        retryIf: RetryHandler.shouldRetryOnError,
        maxAttempts: 3,
        onRetry: (attempt, error) {
          LoggerService.warning('📚 获取培养方案失败，正在重试 (尝试 $attempt/3): $error');
        },
      );
    } catch (e) {
      LoggerService.error('📚 获取培养方案失败', error: e);
      return ErrorHandler.handleError(e, '获取培养方案失败');
    }
  }

  /// 执行获取培养方案的实际操作
  Future<UniResponse<PlanCompletionInfo>> _performGetPlanCompletion() async {
    try {
      final url = config.toFullUrl(endpoints['plan']!);
      LoggerService.info('📚 正在获取培养方案: $url');

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

      LoggerService.info('📚 开始解析HTML数据...');

      // 在 compute 隔离中解析 HTML
      final planInfo = await compute(_parseHtmlInIsolate, htmlContent);

      LoggerService.info('📚 培养方案获取成功');
      return UniResponse.success(planInfo, message: '培养方案获取成功');
    } catch (e) {
      LoggerService.error('📚 网络请求失败', error: e);
      rethrow;
    }
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
