import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import '../../models/jwc/exam_info.dart';
import '../../providers/exam_provider.dart';
import '../widgets/winui_card.dart';
import '../widgets/winui_loading.dart';
import '../widgets/winui_empty_state.dart';
import '../widgets/winui_dialogs.dart';

/// WinUI 风格的考试信息页面
///
/// 使用 Expander 展示考试信息（按日期分组）
/// 复用 ExamProvider 进行数据管理
/// _Requirements: 4.1, 4.2, 4.3, 4.4_
class WinUIExamPage extends StatefulWidget {
  const WinUIExamPage({super.key});

  @override
  State<WinUIExamPage> createState() => _WinUIExamPageState();
}

class _WinUIExamPageState extends State<WinUIExamPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    final provider = Provider.of<ExamProvider>(context, listen: false);
    await provider.loadData(forceRefresh: forceRefresh);

    if (mounted && provider.state == ExamState.error) {
      _showErrorDialog(provider.errorMessage ?? '加载失败', provider.isRetryable);
    }
  }

  Future<void> _refreshData() async {
    await _loadData(forceRefresh: true);
  }

  void _showErrorDialog(String message, bool retryable) {
    WinUIErrorDialog.show(
      context,
      message: message,
      retryable: retryable,
      onRetry: () => _loadData(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ExamProvider>(
      builder: (context, provider, child) {
        return ScaffoldPage(
          header: PageHeader(
            title: const Text('考试安排'),
            commandBar: CommandBar(
              mainAxisAlignment: MainAxisAlignment.end,
              primaryItems: [
                CommandBarButton(
                  icon: const Icon(FluentIcons.refresh),
                  label: const Text('刷新'),
                  onPressed: _refreshData,
                ),
              ],
            ),
          ),
          content: _buildContent(context, provider),
        );
      },
    );
  }

  /// 构建页面内容
  Widget _buildContent(BuildContext context, ExamProvider provider) {
    // 加载中状态
    if (provider.state == ExamState.loading) {
      return const WinUILoading(message: '正在加载考试信息');
    }

    // 加载完成状态
    if (provider.state == ExamState.loaded) {
      if (provider.exams.isEmpty) {
        return WinUIEmptyState.noExams(
          title: '暂时无考试',
          description: '当前没有安排考试',
          onAction: _refreshData,
        );
      }
      return _buildExamList(context, provider);
    }

    // 错误状态
    if (provider.state == ExamState.error) {
      return WinUIEmptyState.needRefresh(
        title: '数据加载失败',
        description: provider.errorMessage ?? '请点击刷新重新加载',
        onAction: _refreshData,
      );
    }

    // 初始状态
    return WinUIEmptyState.noData(
      title: '暂无数据',
      description: '点击右上角刷新按钮加载数据',
      actionText: '刷新',
      onAction: _refreshData,
    );
  }

  /// 构建考试列表（按日期分组）
  Widget _buildExamList(BuildContext context, ExamProvider provider) {
    // 按日期分组
    final groupedExams = <String, List<UnifiedExamInfo>>{};
    for (final exam in provider.exams) {
      final date = exam.examDate;
      groupedExams.putIfAbsent(date, () => []).add(exam);
    }

    // 按日期排序
    final sortedDates = groupedExams.keys.toList()..sort();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 统计信息卡片
          _buildSummaryCard(context, provider),
          const SizedBox(height: 16),
          // 考试列表
          ...sortedDates.map((date) {
            final exams = groupedExams[date]!;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildDateExpander(context, date, exams),
            );
          }),
        ],
      ),
    );
  }

  /// 构建统计信息卡片
  Widget _buildSummaryCard(BuildContext context, ExamProvider provider) {
    final fluentTheme = FluentTheme.of(context);

    // 统计校统考和其他考试数量
    int schoolExamCount = 0;
    int otherExamCount = 0;
    for (final exam in provider.exams) {
      if (exam.examType == '校统考') {
        schoolExamCount++;
      } else {
        otherExamCount++;
      }
    }

    return WinUICard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                FluentIcons.test_plan,
                size: 20,
                color: fluentTheme.accentColor,
              ),
              const SizedBox(width: 8),
              Text(
                '考试统计',
                style: fluentTheme.typography.subtitle,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  context,
                  '总计',
                  '${provider.totalCount}',
                  FluentIcons.calendar,
                  fluentTheme.accentColor,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatItem(
                  context,
                  '校统考',
                  '$schoolExamCount',
                  FluentIcons.education,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatItem(
                  context,
                  '其他考试',
                  '$otherExamCount',
                  FluentIcons.clipboard_list,
                  Colors.orange,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建统计项
  Widget _buildStatItem(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    final theme = FluentTheme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.typography.title?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: theme.typography.caption?.copyWith(
              color: theme.inactiveColor,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建日期分组展开器
  Widget _buildDateExpander(
    BuildContext context,
    String date,
    List<UnifiedExamInfo> exams,
  ) {
    final theme = FluentTheme.of(context);

    return WinUICard(
      padding: EdgeInsets.zero,
      child: Expander(
        initiallyExpanded: true,
        header: Row(
          children: [
            Icon(
              FluentIcons.calendar,
              size: 16,
              color: theme.accentColor,
            ),
            const SizedBox(width: 8),
            Text(
              _formatDate(date),
              style: theme.typography.bodyStrong,
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${exams.length} 场',
                style: theme.typography.caption?.copyWith(
                  color: theme.accentColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          children: exams.map((exam) => _buildExamItem(context, exam)).toList(),
        ),
      ),
    );
  }

  /// 构建考试项
  Widget _buildExamItem(BuildContext context, UnifiedExamInfo exam) {
    final theme = FluentTheme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.resources.controlStrokeColorDefault,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行
          Row(
            children: [
              _buildExamTypeBadge(context, exam.examType),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  exam.courseName,
                  style: theme.typography.body?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 信息行
          Row(
            children: [
              Expanded(
                child: _buildInfoItem(
                  context,
                  FluentIcons.clock,
                  exam.examTime,
                ),
              ),
              Expanded(
                child: _buildInfoItem(
                  context,
                  FluentIcons.poi,
                  exam.examLocation,
                ),
              ),
            ],
          ),
          // 座位号
          if (exam.note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    FluentIcons.event_accepted,
                    size: 12,
                    color: Colors.green,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    exam.note,
                    style: theme.typography.caption?.copyWith(
                      color: Colors.green,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 构建考试类型标签
  Widget _buildExamTypeBadge(BuildContext context, String examType) {
    final isSchoolExam = examType == '校统考';
    final color = isSchoolExam ? Colors.blue : Colors.orange;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        examType,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// 构建信息项
  Widget _buildInfoItem(BuildContext context, IconData icon, String text) {
    final theme = FluentTheme.of(context);

    return Row(
      children: [
        Icon(
          icon,
          size: 14,
          color: theme.inactiveColor,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            style: theme.typography.caption?.copyWith(
              color: theme.inactiveColor,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// 格式化日期
  String _formatDate(String date) {
    try {
      final parts = date.split('-');
      if (parts.length == 3) {
        final month = int.parse(parts[1]);
        final day = int.parse(parts[2]);
        final weekday = _getWeekday(date);
        return '$month月$day日 $weekday';
      }
    } catch (e) {
      // 解析失败，返回原始日期
    }
    return date;
  }

  /// 获取星期几
  String _getWeekday(String date) {
    try {
      final dateTime = DateTime.parse(date);
      const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
      return weekdays[dateTime.weekday - 1];
    } catch (e) {
      return '';
    }
  }
}
