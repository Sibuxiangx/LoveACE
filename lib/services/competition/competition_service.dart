import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html_dom;

import '../../models/backend/uni_response.dart';
import '../../models/competition/competition_full_response.dart';
import '../../models/competition/award_project.dart';
import '../../models/competition/credits_summary.dart';
import '../../utils/error_handler.dart';
import '../../utils/retry_handler.dart';
import '../aufe/connector.dart';
import '../logger_service.dart';
import 'competition_config.dart';

/// 竞赛信息服务
///
/// 提供学科竞赛获奖信息和学分汇总的查询功能
/// 使用两步请求流程处理ASP.NET表单，并在compute隔离中解析HTML
class CompetitionService {
  final AUFEConnection connection;
  final CompetitionConfig config;

  /// API端点常量
  static const Map<String, String> endpoints = {'awards': '/xsXmMain.aspx'};

  CompetitionService(this.connection, this.config);

  /// 获取完整竞赛信息
  ///
  /// 返回包含获奖项目列表和学分汇总的响应
  /// 使用两步请求流程和compute隔离进行HTML解析
  ///
  /// 成功时返回 UniResponse.success，包含 CompetitionFullResponse 数据
  /// 失败时返回 UniResponse.failure，根据错误类型设置 retryable 标志
  Future<UniResponse<CompetitionFullResponse>> getCompetitionInfo() async {
    try {
      return await RetryHandler.retry(
        operation: () async => await _performGetCompetitionInfo(),
        retryIf: RetryHandler.shouldRetryOnError,
        maxAttempts: 3,
        onRetry: (attempt, error) {
          LoggerService.warning('🏆 获取竞赛信息失败，正在重试 (尝试 $attempt/3): $error');
        },
      );
    } catch (e) {
      LoggerService.error('🏆 获取竞赛信息失败', error: e);
      return ErrorHandler.handleError(e, '获取竞赛信息失败');
    }
  }

  /// 执行获取竞赛信息的实际操作
  ///
  /// 两步请求流程：
  /// 1. GET请求获取初始页面和ASP.NET表单数据
  /// 2. POST请求提交表单数据获取实际内容
  Future<UniResponse<CompetitionFullResponse>>
  _performGetCompetitionInfo() async {
    try {
      // 使用配置中的完整URL
      final url = config.toFullUrl(endpoints['awards']!);
      LoggerService.info('🏆 正在获取竞赛信息');

      // 检查UAAP登录状态（竞赛系统需要UAAP认证）
      final uaapStatus = await connection.checkUaapLoginStatus();
      if (!uaapStatus.isLoggedIn) {
        LoggerService.error('🏆 UAAP未登录或会话已过期');
        throw Exception('UAAP未登录或会话已过期，请重新登录');
      }

      // 第一步：GET请求获取初始页面和表单数据
      final indexResponse = await connection.client.get(url);

      // 提取响应HTML
      String indexHtml = indexResponse.data;
      if (indexHtml.isEmpty) {
        throw Exception('初始页面响应为空');
      }

      // 检查是否是VPN重定向页面
      if (indexHtml.contains('var g_lines = []') ||
          indexHtml.contains('selectline_timeout') ||
          (indexHtml.contains('Your browser does not support JavaScript') &&
              indexHtml.contains('<script>') &&
              indexHtml.length < 10000)) {
        LoggerService.error('🏆 收到VPN重定向页面，会话可能已过期');
        throw Exception('VPN会话已过期，请重新登录');
      }

      // 检查是否是登录页面
      if (indexHtml.contains('用户登录') ||
          (indexHtml.contains('login') && indexHtml.contains('password'))) {
        LoggerService.error('🏆 收到登录页面，需要重新认证');
        throw Exception('需要重新登录');
      }

      // 在compute中提取表单数据
      final formData = await compute(_extractFormDataInIsolate, indexHtml);

      if (formData['__VIEWSTATE'] == null || formData['__VIEWSTATE']!.isEmpty) {
        LoggerService.error('🏆 未找到 __VIEWSTATE 字段');
        throw Exception('无法获取表单数据，页面格式可能已变更');
      }

      // 第二步：POST请求提交表单数据
      final resultResponse = await connection.client.post(
        url,
        data: formData,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        ),
      );

      // 提取响应HTML
      String resultHtml = resultResponse.data;
      if (resultHtml.isEmpty) {
        throw Exception('竞赛信息响应为空');
      }

      // 在compute中解析HTML
      final parsed = await compute(_parseHtmlInIsolate, resultHtml);

      LoggerService.info('🏆 竞赛信息获取成功，共 ${parsed.totalAwardsCount} 项获奖');
      return UniResponse.success(parsed, message: '获取竞赛信息成功');
    } catch (e) {
      LoggerService.error('🏆 网络请求失败', error: e);
      rethrow;
    }
  }

  /// 在compute隔离中提取ASP.NET表单数据
  ///
  /// 参数：HTML字符串
  /// 返回：表单数据Map
  static Map<String, String> _extractFormDataInIsolate(String html) {
    final document = html_parser.parse(html);

    // 提取隐藏字段
    final viewState = _extractInputValue(document, '__VIEWSTATE');
    final viewStateGenerator = _extractInputValue(
      document,
      '__VIEWSTATEGENERATOR',
    );
    final eventValidation = _extractInputValue(document, '__EVENTVALIDATION');
    final eventTarget = _extractInputValue(document, '__EVENTTARGET');
    final eventArgument = _extractInputValue(document, '__EVENTARGUMENT');
    final lastFocus = _extractInputValue(document, '__LASTFOCUS');

    // 构建表单数据
    // 使用原始字符串 r'' 来避免 $ 符号被解释为字符串插值
    // 注意：必须强制设置 __EVENTTARGET 为"已申报奖项"标签，即使原值为空字符串
    return {
      '__VIEWSTATE': viewState ?? '',
      '__VIEWSTATEGENERATOR': viewStateGenerator ?? '',
      '__EVENTVALIDATION': eventValidation ?? '',
      '__EVENTTARGET': (eventTarget != null && eventTarget.isNotEmpty)
          ? eventTarget
          : r'ctl00$ContentPlaceHolder1$ContentPlaceHolder2$DataList1$ctl01$LinkButton1',
      '__EVENTARGUMENT': eventArgument ?? '',
      '__LASTFOCUS': lastFocus ?? '',
      // 添加其他必需的表单字段（参考 Python 实现）
      r'ctl00$ContentPlaceHolder1$ContentPlaceHolder2$ddlSslb': '%',
      r'ctl00$ContentPlaceHolder1$ContentPlaceHolder2$txtSsmc': '',
      r'ctl00$ContentPlaceHolder1$ContentPlaceHolder2$gvSb$ctl28$txtNewPageIndex':
          '1',
    };
  }

  /// 提取input元素的value值
  static String? _extractInputValue(html_dom.Document document, String name) {
    final input = document.querySelector('input[name="$name"]');
    return input?.attributes['value'];
  }

  /// 在compute隔离中执行的HTML解析函数
  ///
  /// 参数：HTML字符串
  /// 返回：解析后的CompetitionFullResponse对象
  static CompetitionFullResponse _parseHtmlInIsolate(String html) {
    final document = html_parser.parse(html);

    // 解析学生ID
    final studentId = _parseStudentId(document);

    // 解析获奖项目列表
    final awards = _parseAwardProjects(document);

    // 解析学分汇总
    final creditsSummary = _parseCreditsSummary(document);

    return CompetitionFullResponse(
      studentId: studentId,
      totalAwardsCount: awards.length,
      awards: awards,
      creditsSummary: creditsSummary,
    );
  }

  /// 解析学生ID
  ///
  /// 从span元素中提取学生ID/工号
  /// 格式: "欢迎您：20244787"
  static String _parseStudentId(html_dom.Document document) {
    try {
      // 根据Python代码，查找ID为ContentPlaceHolder1_lblXM的span
      final studentSpan =
          document.querySelector('span#ContentPlaceHolder1_lblXM') ??
          document.querySelector('span[id*="lblXM"]') ??
          document.querySelector('span[id*="lblXh"]');

      if (studentSpan != null) {
        final text = studentSpan.text.trim();
        if (text.isNotEmpty) {
          // 处理 "欢迎您：20244787" 格式
          if (text.contains('：')) {
            final parts = text.split('：');
            if (parts.length > 1) {
              return parts[1].trim();
            }
          }
          // 如果没有冒号，直接返回文本
          return text;
        }
      }

      LoggerService.warning('🏆 未找到学生ID元素');
      return '';
    } catch (e) {
      LoggerService.warning('🏆 解析学生ID失败: $e');
      return '';
    }
  }

  /// 解析获奖项目列表
  ///
  /// 从表格ContentPlaceHolder1_ContentPlaceHolder2_gvHj中提取所有获奖项目
  static List<AwardProject> _parseAwardProjects(html_dom.Document document) {
    final projects = <AwardProject>[];

    try {
      final allTables = document.querySelectorAll('table');

      // 尝试多种方式查找表格
      html_dom.Element? table;

      // 方法1: 通过完整ID查找
      table = document.querySelector(
        'table#ContentPlaceHolder1_ContentPlaceHolder2_gvHj',
      );

      // 方法2: 通过部分ID查找
      table ??= document.querySelector('table[id*="gvHj"]');

      // 方法3: 通过caption文本查找
      if (table == null) {
        for (final t in allTables) {
          final caption = t.querySelector('caption');
          if (caption != null && caption.text.contains('当前已经进行获奖申报的项目列表')) {
            table = t;
            break;
          }
        }
      }

      if (table == null) {
        LoggerService.warning('🏆 未找到获奖项目表格');
        return projects;
      }

      final rows = table.querySelectorAll('tr');

      // 跳过表头行（第一行）
      for (var i = 1; i < rows.length; i++) {
        final cells = rows[i].querySelectorAll('td');

        // 表格有15列：申报ID, 项目名称, 级别, 等级, 取得日期, 申报人, 姓名, 排序, 学分, 奖励金, 申报状态, 学校审核, 删除, 查看/编辑, 毕设替代
        // 我们需要前12列的数据
        if (cells.length < 12) {
          continue;
        }

        try {
          // 解析每个字段（索引0-11）
          final projectId = cells[0].text.trim();
          final projectName = cells[1].text.trim();
          final level = cells[2].text.trim();
          final grade = cells[3].text.trim();
          final awardDate = cells[4].text.trim();
          final applicantId = cells[5].text.trim();
          final applicantName = cells[6].text.trim();
          final order = int.tryParse(cells[7].text.trim()) ?? 0;
          final credits = double.tryParse(cells[8].text.trim()) ?? 0.0;
          final bonus = double.tryParse(cells[9].text.trim()) ?? 0.0;
          final status = cells[10].text.trim();
          final verificationStatus = cells[11].text.trim();

          projects.add(
            AwardProject(
              projectId: projectId,
              projectName: projectName,
              level: level,
              grade: grade,
              awardDate: awardDate,
              applicantId: applicantId,
              applicantName: applicantName,
              order: order,
              credits: credits,
              bonus: bonus,
              status: status,
              verificationStatus: verificationStatus,
            ),
          );
        } catch (e) {
          LoggerService.warning('🏆 解析项目行失败: $e');
          continue;
        }
      }
    } catch (e) {
      LoggerService.error('🏆 解析获奖项目列表失败', error: e);
    }

    return projects;
  }

  /// 解析学分汇总
  ///
  /// 从6个span元素中提取各类学分值
  static CreditsSummary? _parseCreditsSummary(html_dom.Document document) {
    try {
      return CreditsSummary(
        disciplineCompetitionCredits: _parseCredit(
          document,
          'ContentPlaceHolder1_ContentPlaceHolder2_lblXkjsxf',
        ),
        scientificResearchCredits: _parseCredit(
          document,
          'ContentPlaceHolder1_ContentPlaceHolder2_lblKyxf',
        ),
        transferableCompetitionCredits: _parseCredit(
          document,
          'ContentPlaceHolder1_ContentPlaceHolder2_lblKzjslxf',
        ),
        innovationPracticeCredits: _parseCredit(
          document,
          'ContentPlaceHolder1_ContentPlaceHolder2_lblCxcyxf',
        ),
        abilityCertificationCredits: _parseCredit(
          document,
          'ContentPlaceHolder1_ContentPlaceHolder2_lblNlzgxf',
        ),
        otherProjectCredits: _parseCredit(
          document,
          'ContentPlaceHolder1_ContentPlaceHolder2_lblQtxf',
        ),
      );
    } catch (e) {
      LoggerService.error('🏆 解析学分汇总失败', error: e);
      return null;
    }
  }

  /// 解析单个学分值
  ///
  /// 处理"无"和空值情况，返回null或double值
  static double? _parseCredit(html_dom.Document document, String spanId) {
    try {
      final span = document.querySelector('span[id="$spanId"]');
      if (span == null) {
        return null;
      }

      final text = span.text.trim();
      if (text.isEmpty || text == '无') {
        return null;
      }

      return double.tryParse(text);
    } catch (e) {
      LoggerService.warning('🏆 解析学分值失败 ($spanId): $e');
      return null;
    }
  }
}
