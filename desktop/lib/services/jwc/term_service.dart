import 'package:html/parser.dart' as html_parser;
import '../../models/backend/uni_response.dart';
import '../../models/jwc/term_item.dart';
import '../../utils/error_handler.dart';
import '../../utils/retry_handler.dart';
import '../aufe/connector.dart';
import '../logger_service.dart';
import 'jwc_config.dart';

/// 学期信息服务
///
/// 提供学期列表查询功能
class TermService {
  final AUFEConnection connection;
  final JWCConfig config;

  /// API端点常量
  static const Map<String, String> endpoints = {
    'allTerms': '/student/courseSelect/calendarSemesterCurriculum/index',
    'calendar': '/indexCalendar',
  };

  TermService(this.connection, this.config);

  /// 获取所有可查询的学期列表
  ///
  /// 从HTML页面解析学期选择框，提取学期代码和名称
  /// 列表第一项为当前学期
  ///
  /// 成功时返回 UniResponse.success，包含 List<TermItem> 数据
  /// 失败时返回 UniResponse.failure，根据错误类型设置 retryable 标志
  Future<UniResponse<List<TermItem>>> getAllTerms() async {
    try {
      return await RetryHandler.retry(
        operation: () async => await _performGetAllTerms(),
        retryIf: RetryHandler.shouldRetryOnError,
        maxAttempts: 3,
        onRetry: (attempt, error) {
          LoggerService.warning('📅 获取学期列表失败，正在重试 (尝试 $attempt/3): $error');
        },
      );
    } catch (e) {
      LoggerService.error('📅 获取学期列表失败', error: e);
      return ErrorHandler.handleError(e, '获取学期列表失败');
    }
  }

  /// 执行获取学期列表的实际操作
  Future<UniResponse<List<TermItem>>> _performGetAllTerms() async {
    try {
      final url = config.toFullUrl(endpoints['allTerms']!);
      LoggerService.info('📅 正在获取学期列表: $url');

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

      // 查找学期选择框 (select#planCode)
      final selectElement = document.querySelector('select#planCode');
      if (selectElement == null) {
        throw Exception('未找到学期选择框 (select#planCode)');
      }

      // 提取所有option元素
      final options = selectElement.querySelectorAll('option');
      if (options.isEmpty) {
        throw Exception('学期选择框中没有选项');
      }

      // 解析学期列表
      final termList = <TermItem>[];
      for (int i = 0; i < options.length; i++) {
        final option = options[i];
        final termCode = option.attributes['value'];
        final termText = option.text.trim();

        if (termCode == null || termCode.isEmpty) {
          continue; // 跳过空值选项
        }

        // 处理学期名称格式转换（春→下，秋→上）
        var termName = termText;
        termName = termName.replaceAll('春', '下');
        termName = termName.replaceAll('秋', '上');

        // 第一项为当前学期
        final isCurrent = (i == 0);

        termList.add(
          TermItem(
            termCode: termCode,
            termName: termName,
            isCurrent: isCurrent,
          ),
        );
      }

      if (termList.isEmpty) {
        throw Exception('未能解析出任何学期信息');
      }

      LoggerService.info('📅 学期列表获取成功，共 ${termList.length} 个学期');
      return UniResponse.success(termList, message: '学期列表获取成功');
    } catch (e) {
      LoggerService.error('📅 网络请求失败', error: e);
      rethrow;
    }
  }
}
