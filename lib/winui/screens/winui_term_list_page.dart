import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import '../../models/jwc/term_item.dart';
import '../../models/jwc/term_score_response.dart';
import '../../models/jwc/score_record.dart';
import '../../providers/term_provider.dart';
import '../../providers/term_score_provider.dart';
import '../../services/logger_service.dart';
import '../widgets/winui_card.dart';
import '../widgets/winui_loading.dart';
import '../widgets/winui_empty_state.dart';
import '../widgets/winui_dialogs.dart';
import '../widgets/winui_notification.dart';

/// WinUI 风格的学期成绩页面
///
/// 使用 Master-Detail 布局：左侧学期列表，右侧成绩详情
/// 复用 TermProvider 和 TermScoreProvider 进行数据管理
/// _Requirements: 6.1, 6.2, 6.3, 6.4_
class WinUITermListPage extends StatefulWidget {
  const WinUITermListPage({super.key});

  @override
  State<WinUITermListPage> createState() => _WinUITermListPageState();
}

class _WinUITermListPageState extends State<WinUITermListPage> {
  /// 当前选中的学期
  TermItem? _selectedTerm;

  /// 排序列
  String? _sortColumn;

  /// 是否升序
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    final provider = Provider.of<TermProvider>(context, listen: false);
    await provider.loadData(forceRefresh: forceRefresh);

    if (mounted && provider.state == TermState.error) {
      _showErrorDialog(provider.errorMessage ?? '加载失败', provider.isRetryable);
    }
  }

  Future<void> _refreshData() async {
    setState(() {
      _selectedTerm = null;
    });
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

  /// 选择学期并加载成绩
  Future<void> _selectTerm(TermItem term) async {
    setState(() {
      _selectedTerm = term;
      _sortColumn = null;
      _sortAscending = true;
    });

    // 加载该学期的成绩
    final scoreProvider = Provider.of<TermScoreProvider?>(context, listen: false);
    if (scoreProvider != null) {
      await scoreProvider.loadScore(term.termCode, forceRefresh: false);

      if (mounted && scoreProvider.state == TermScoreState.error) {
        _showErrorDialog(scoreProvider.errorMessage ?? '加载成绩失败', scoreProvider.isRetryable);
      }
    }
  }

  /// 刷新成绩
  Future<void> _refreshScores() async {
    if (_selectedTerm == null) return;

    final scoreProvider = Provider.of<TermScoreProvider?>(context, listen: false);
    if (scoreProvider != null) {
      await scoreProvider.loadScore(_selectedTerm!.termCode, forceRefresh: true);

      if (mounted && scoreProvider.state == TermScoreState.error) {
        _showErrorDialog(scoreProvider.errorMessage ?? '加载成绩失败', scoreProvider.isRetryable);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TermProvider>(
      builder: (context, provider, child) {
        return ScaffoldPage(
          header: PageHeader(
            title: const Text('学期成绩'),
            commandBar: CommandBar(
              mainAxisAlignment: MainAxisAlignment.end,
              primaryItems: [
                if (_selectedTerm != null)
                  CommandBarButton(
                    icon: const Icon(FluentIcons.download),
                    label: const Text('导出CSV'),
                    onPressed: _exportCSV,
                  ),
                CommandBarButton(
                  icon: const Icon(FluentIcons.refresh),
                  label: const Text('刷新'),
                  onPressed: _selectedTerm != null ? _refreshScores : _refreshData,
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
  Widget _buildContent(BuildContext context, TermProvider provider) {
    // 加载中状态
    if (provider.state == TermState.loading) {
      return const WinUILoading(message: '正在加载学期列表');
    }

    // 加载完成状态
    if (provider.state == TermState.loaded && provider.termList != null) {
      return _buildMainLayout(context, provider);
    }

    // 错误状态
    if (provider.state == TermState.error) {
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

  /// 构建主布局（左侧学期列表 + 右侧成绩详情）
  Widget _buildMainLayout(BuildContext context, TermProvider provider) {
    final termList = provider.termList!;
    final currentTerms = termList.where((t) => t.isCurrent).toList();
    final historyTerms = termList.where((t) => !t.isCurrent).toList();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左侧：学期列表
        SizedBox(
          width: 280,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (currentTerms.isNotEmpty) ...[
                  _buildSectionTitle(context, '当前学期'),
                  const SizedBox(height: 12),
                  ...currentTerms.map((term) => _buildTermCard(context, term, isCurrent: true)),
                  const SizedBox(height: 16),
                ],
                if (historyTerms.isNotEmpty) ...[
                  _buildSectionTitle(context, '历史学期'),
                  const SizedBox(height: 12),
                  ...historyTerms.map((term) => _buildTermCard(context, term)),
                ],
              ],
            ),
          ),
        ),
        // 分隔线
        Container(
          width: 1,
          color: FluentTheme.of(context).resources.controlStrokeColorDefault,
        ),
        // 右侧：成绩详情
        Expanded(
          child: _buildScoreDetail(context),
        ),
      ],
    );
  }

  /// 构建分区标题
  Widget _buildSectionTitle(BuildContext context, String title) {
    final theme = FluentTheme.of(context);

    return Row(
      children: [
        Icon(
          title == '当前学期' ? FluentIcons.favorite_star : FluentIcons.history,
          size: 16,
          color: theme.accentColor,
        ),
        const SizedBox(width: 8),
        Text(title, style: theme.typography.subtitle),
      ],
    );
  }

  /// 构建学期卡片
  Widget _buildTermCard(BuildContext context, TermItem term, {bool isCurrent = false}) {
    final theme = FluentTheme.of(context);
    final isSelected = _selectedTerm?.termCode == term.termCode;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Button(
        onPressed: () => _selectTerm(term),
        style: ButtonStyle(padding: WidgetStateProperty.all(EdgeInsets.zero)),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: isSelected ? theme.accentColor.withValues(alpha: 0.15) : null,
            border: Border.all(
              color: isSelected ? theme.accentColor : theme.resources.controlStrokeColorDefault,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isCurrent ? FluentIcons.favorite_star : FluentIcons.calendar,
                size: 16,
                color: isCurrent ? theme.accentColor : theme.inactiveColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  term.termName,
                  style: theme.typography.body?.copyWith(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ),
              if (isSelected)
                Icon(FluentIcons.chevron_right, size: 14, color: theme.accentColor),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建成绩详情面板
  Widget _buildScoreDetail(BuildContext context) {
    final theme = FluentTheme.of(context);

    if (_selectedTerm == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(FluentIcons.touch_pointer, size: 64, color: theme.inactiveColor),
            const SizedBox(height: 16),
            Text('选择左侧学期查看成绩', style: theme.typography.subtitle?.copyWith(color: theme.inactiveColor)),
            const SizedBox(height: 8),
            Text('点击学期卡片查看详细成绩', style: theme.typography.body?.copyWith(color: theme.inactiveColor.withValues(alpha: 0.7))),
          ],
        ),
      );
    }

    return Consumer<TermScoreProvider?>(
      builder: (context, scoreProvider, child) {
        if (scoreProvider == null) {
          return WinUIEmptyState.noData(title: '暂无数据', description: '请先登录');
        }

        if (scoreProvider.state == TermScoreState.loading) {
          return const WinUILoading(message: '正在加载成绩');
        }

        if (scoreProvider.state == TermScoreState.loaded && scoreProvider.scoreData != null) {
          return _buildScoreTable(context, scoreProvider.scoreData!);
        }

        if (scoreProvider.state == TermScoreState.error) {
          return WinUIEmptyState.needRefresh(
            title: '成绩加载失败',
            description: scoreProvider.errorMessage ?? '请点击刷新重新加载',
            onAction: _refreshScores,
          );
        }

        return WinUIEmptyState.noData(
          title: '暂无成绩',
          description: '该学期暂无成绩数据',
        );
      },
    );
  }

  /// 构建成绩表格
  Widget _buildScoreTable(BuildContext context, TermScoreResponse scoreData) {
    final theme = FluentTheme.of(context);
    final records = _getSortedRecords(scoreData.records);

    // 计算统计信息
    double totalCredits = 0;
    double totalWeightedScore = 0;
    int validCount = 0;

    for (final record in records) {
      final credit = double.tryParse(record.credits) ?? 0;
      final score = double.tryParse(record.score) ?? 0;
      if (credit > 0 && score > 0) {
        totalCredits += credit;
        totalWeightedScore += credit * score;
        validCount++;
      }
    }

    final avgScore = totalCredits > 0 ? totalWeightedScore / totalCredits : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 学期标题和统计卡片
          WinUICard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          FluentIcons.education,
                          size: 20,
                          color: theme.accentColor,
                        ),
                        const SizedBox(width: 10),
                        Text(_selectedTerm!.termName, style: theme.typography.subtitle),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: theme.accentColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: theme.accentColor.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        '${records.length} 门课程',
                        style: TextStyle(
                          color: theme.accentColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // 统计信息卡片
                Row(
                  children: [
                    Expanded(child: _buildStatCard(context, '加权平均分', avgScore.toStringAsFixed(2), FluentIcons.calculator)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildStatCard(context, '总学分', totalCredits.toStringAsFixed(1), FluentIcons.badge)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildStatCard(context, '课程数', validCount.toString(), FluentIcons.library)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // 成绩列表
          WinUICard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                // 表头
                _buildTableHeader(context),
                // 表格内容
                ...records.asMap().entries.map((entry) => _buildTableRow(context, entry.value, entry.key, records.length)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建统计卡片
  Widget _buildStatCard(BuildContext context, String label, String value, IconData icon) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.resources.controlStrokeColorDefault.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: theme.inactiveColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.typography.caption?.copyWith(
                  color: theme.inactiveColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.typography.subtitle?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final headerStyle = theme.typography.caption?.copyWith(
      fontWeight: FontWeight.w600,
      color: theme.inactiveColor,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.black.withValues(alpha: 0.02),
        border: Border(
          bottom: BorderSide(
            color: theme.resources.controlStrokeColorDefault.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(flex: 4, child: _buildSortableHeader(context, '课程名称', 'courseName', headerStyle)),
          Expanded(flex: 1, child: _buildSortableHeader(context, '学分', 'credit', headerStyle)),
          Expanded(flex: 1, child: _buildSortableHeader(context, '成绩', 'score', headerStyle)),
          Expanded(flex: 2, child: Text('课程类型', style: headerStyle)),
        ],
      ),
    );
  }

  Widget _buildSortableHeader(BuildContext context, String title, String column, TextStyle? style) {
    final theme = FluentTheme.of(context);
    final isActive = _sortColumn == column;

    return HoverButton(
      onPressed: () {
        setState(() {
          if (_sortColumn == column) {
            _sortAscending = !_sortAscending;
          } else {
            _sortColumn = column;
            _sortAscending = true;
          }
        });
      },
      cursor: SystemMouseCursors.click,
      builder: (context, states) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: style?.copyWith(
                color: isActive ? theme.accentColor : (states.isHovering ? theme.accentColor.withValues(alpha: 0.7) : null),
              ),
            ),
            const SizedBox(width: 4),
            if (isActive)
              Icon(
                _sortAscending ? FluentIcons.sort_up : FluentIcons.sort_down,
                size: 10,
                color: theme.accentColor,
              ),
          ],
        );
      },
    );
  }

  Widget _buildTableRow(BuildContext context, ScoreRecord record, int index, int total) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isLast = index == total - 1;

    return HoverButton(
      onPressed: () {},
      cursor: SystemMouseCursors.basic,
      builder: (context, states) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: states.isHovering
                ? (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04))
                : null,
            border: isLast
                ? null
                : Border(
                    bottom: BorderSide(
                      color: theme.resources.controlStrokeColorDefault.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Text(
                  record.courseNameCn,
                  style: theme.typography.body?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                flex: 1,
                child: Text(
                  record.credits,
                  style: theme.typography.body?.copyWith(
                    color: theme.inactiveColor,
                  ),
                ),
              ),
              Expanded(
                flex: 1,
                child: _buildScoreBadge(context, record.score),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  record.courseType ?? '',
                  style: theme.typography.body?.copyWith(
                    color: theme.inactiveColor,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 构建成绩徽章
  Widget _buildScoreBadge(BuildContext context, String scoreStr) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final scoreColor = _getScoreColor(scoreStr, isDark);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scoreColor.withValues(alpha: isDark ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        scoreStr,
        style: TextStyle(
          color: scoreColor,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }

  List<ScoreRecord> _getSortedRecords(List<ScoreRecord> records) {
    if (_sortColumn == null) return records;

    final sorted = List<ScoreRecord>.from(records);
    sorted.sort((a, b) {
      int result;
      switch (_sortColumn) {
        case 'courseName':
          result = a.courseNameCn.compareTo(b.courseNameCn);
          break;
        case 'credit':
          result = (double.tryParse(a.credits) ?? 0).compareTo(double.tryParse(b.credits) ?? 0);
          break;
        case 'score':
          result = (double.tryParse(a.score) ?? 0).compareTo(double.tryParse(b.score) ?? 0);
          break;
        default:
          result = 0;
      }
      return _sortAscending ? result : -result;
    });
    return sorted;
  }

  /// 获取成绩颜色（柔和版本）
  Color _getScoreColor(String scoreStr, bool isDark) {
    final score = double.tryParse(scoreStr);
    if (score == null) return Colors.grey;

    // 使用更柔和的颜色
    if (score >= 90) {
      return isDark ? const Color(0xFF4CAF50) : const Color(0xFF2E7D32);
    }
    if (score >= 80) {
      return isDark ? const Color(0xFF42A5F5) : const Color(0xFF1976D2);
    }
    if (score >= 70) {
      return isDark ? const Color(0xFFFFB74D) : const Color(0xFFF57C00);
    }
    if (score >= 60) {
      return isDark ? const Color(0xFFFFD54F) : const Color(0xFFFFA000);
    }
    return isDark ? const Color(0xFFEF5350) : const Color(0xFFD32F2F);
  }

  /// 导出 CSV
  Future<void> _exportCSV() async {
    if (_selectedTerm == null) return;

    final scoreProvider = Provider.of<TermScoreProvider?>(context, listen: false);
    if (scoreProvider == null || scoreProvider.scoreData == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('导出成绩'),
        content: Text('确认导出 ${_selectedTerm!.termName} 的成绩为CSV文件？'),
        actions: [
          Button(child: const Text('取消'), onPressed: () => Navigator.of(context).pop(false)),
          FilledButton(child: const Text('导出'), onPressed: () => Navigator.of(context).pop(true)),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ContentDialog(
        title: const Text('正在导出'),
        content: const Row(children: [ProgressRing(), SizedBox(width: 16), Text('正在导出CSV文件...')]),
        actions: const [],
      ),
    );

    try {
      await scoreProvider.exportToCSV();

      if (mounted) {
        Navigator.of(context).pop();
        WinUINotificationManager.showSuccess(context, title: '导出成功', content: 'CSV文件已导出');
      }
    } catch (e) {
      LoggerService.error('❌ 导出CSV失败', error: e);
      if (mounted) {
        Navigator.of(context).pop();
        WinUINotificationManager.showError(context, title: '导出失败', content: e.toString());
      }
    }
  }
}
