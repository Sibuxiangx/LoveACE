import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/term_score_provider.dart';
import '../providers/theme_provider.dart';
import '../models/jwc/score_record.dart';
import '../models/jwc/term_score_response.dart';
import '../widgets/adaptive_sliver_app_bar.dart';
import '../widgets/glass_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/retryable_error_dialog.dart';
import '../widgets/loading_indicator.dart';
import '../widgets/app_background.dart';
import '../widgets/export_confirm_dialog.dart';
import '../services/logger_service.dart';

/// 学期成绩详情页面
///
/// 显示指定学期的所有课程成绩
/// 支持成绩记录的展开/收起查看详细信息
/// 支持自动加载、手动刷新和下拉刷新
/// 满足需求: 3.1, 3.2, 3.3, 3.4, 3.5, 4.1, 4.2, 4.3, 4.4, 4.5, 7.1, 8.2, 9.1
class TermScoreDetailPage extends StatefulWidget {
  /// 学期代码
  final String termCode;

  /// 学期名称
  final String termName;

  const TermScoreDetailPage({
    super.key,
    required this.termCode,
    required this.termName,
  });

  @override
  State<TermScoreDetailPage> createState() => _TermScoreDetailPageState();
}

class _TermScoreDetailPageState extends State<TermScoreDetailPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadScore();
    });
  }

  Future<void> _loadScore({bool forceRefresh = false}) async {
    final provider = Provider.of<TermScoreProvider>(context, listen: false);
    await provider.loadScore(widget.termCode, forceRefresh: forceRefresh);

    if (mounted && provider.state == TermScoreState.error) {
      _showErrorDialog(provider.errorMessage ?? '加载失败', provider.isRetryable);
    }
  }

  Future<void> _refreshData() async {
    await _loadScore(forceRefresh: true);
  }

  void _showErrorDialog(String message, bool retryable) {
    showDialog(
      context: context,
      builder: (context) => RetryableErrorDialog(
        message: message,
        retryable: retryable,
        onRetry: _loadScore,
      ),
    );
  }

  /// 导出CSV
  Future<void> _exportCSV() async {
    await ExportConfirmDialog.show(
      context,
      title: '导出成绩',
      content: '确认导出 ${widget.termName} 的成绩数据为CSV文件？',
      onConfirm: () async {
        try {
          // 显示加载指示器
          if (mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('正在导出...'),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          final provider = Provider.of<TermScoreProvider>(
            context,
            listen: false,
          );
          await provider.exportToCSV();

          // 关闭加载指示器
          if (mounted) {
            Navigator.of(context).pop();

            // 显示成功提示
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white),
                    SizedBox(width: 8),
                    Text('CSV文件导出成功'),
                  ],
                ),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          }
        } catch (e) {
          LoggerService.error('❌ 导出CSV失败', error: e);

          // 关闭加载指示器
          if (mounted) {
            Navigator.of(context).pop();

            // 显示错误提示
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.error, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(child: Text('导出失败: $e')),
                  ],
                ),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final hasBackground = themeProvider.backgroundPath != null;

    return Scaffold(
      backgroundColor: hasBackground ? Colors.transparent : null,
      body: AppBackground(
        child: Consumer<TermScoreProvider>(
          builder: (context, provider, child) {
            // 加载中状态
            if (provider.state == TermScoreState.loading) {
              return CustomScrollView(
                slivers: [
                  AdaptiveSliverAppBar(
                    title: widget.termName,
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: _refreshData,
                        tooltip: '刷新',
                      ),
                    ],
                  ),
                  const SliverLoadingIndicator(message: '正在加载成绩数据...'),
                ],
              );
            }

            // 加载完成状态
            if (provider.state == TermScoreState.loaded &&
                provider.scoreData != null) {
              final scoreData = provider.scoreData!;

              // 检查是否有成绩数据
              if (scoreData.records.isEmpty) {
                return CustomScrollView(
                  slivers: [
                    AdaptiveSliverAppBar(
                      title: widget.termName,
                      actions: [
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: _refreshData,
                          tooltip: '刷新',
                        ),
                      ],
                    ),
                    SliverFillRemaining(
                      child: EmptyState.noData(
                        title: '暂无成绩',
                        description: '该学期暂无成绩记录',
                        actionText: '刷新',
                        onAction: _refreshData,
                      ),
                    ),
                  ],
                );
              }

              return RefreshIndicator(
                onRefresh: _refreshData,
                child: CustomScrollView(
                  slivers: [
                    AdaptiveSliverAppBar(
                      title: widget.termName,
                      actions: [
                        IconButton(
                          icon: const Icon(Icons.file_download),
                          onPressed: _exportCSV,
                          tooltip: '导出CSV',
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: _refreshData,
                          tooltip: '刷新',
                        ),
                      ],
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.all(16),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          // 成绩汇总卡片
                          _buildSummaryCard(scoreData),
                          const SizedBox(height: 16),
                          // 成绩记录列表
                          ...scoreData.records.asMap().entries.map((entry) {
                            final index = entry.key;
                            final record = entry.value;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _buildScoreCard(record, index, provider),
                            );
                          }),
                        ]),
                      ),
                    ),
                  ],
                ),
              );
            }

            // 错误状态
            if (provider.state == TermScoreState.error) {
              return CustomScrollView(
                slivers: [
                  AdaptiveSliverAppBar(
                    title: widget.termName,
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: _refreshData,
                        tooltip: '刷新',
                      ),
                    ],
                  ),
                  SliverFillRemaining(
                    child: EmptyState.needRefresh(
                      title: '数据加载失败',
                      description: provider.errorMessage ?? '请点击刷新重新加载',
                      onAction: _refreshData,
                    ),
                  ),
                ],
              );
            }

            // 初始状态
            return CustomScrollView(
              slivers: [
                AdaptiveSliverAppBar(
                  title: widget.termName,
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _refreshData,
                      tooltip: '刷新',
                    ),
                  ],
                ),
                SliverFillRemaining(
                  child: EmptyState.noData(
                    title: '暂无数据',
                    description: '点击右上角刷新按钮加载数据',
                    actionText: '刷新',
                    onAction: _refreshData,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 构建成绩汇总卡片
  Widget _buildSummaryCard(TermScoreResponse data) {
    // 计算总学分
    double totalCredits = 0;
    for (var record in data.records) {
      try {
        totalCredits += double.parse(record.credits);
      } catch (e) {
        // 忽略无法解析的学分
      }
    }

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.termName,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildStatItem('总课程', '${data.totalCount} 门')),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatItem(
                  '总学分',
                  '${totalCredits.toStringAsFixed(1)} 分',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建统计信息项
  Widget _buildStatItem(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  /// 构建成绩记录卡片（支持展开/收起）
  Widget _buildScoreCard(
    ScoreRecord record,
    int index,
    TermScoreProvider provider,
  ) {
    final isExpanded = provider.isRecordExpanded(index);

    return GlassCard(
      padding: const EdgeInsets.all(0),
      child: Column(
        children: [
          // 标题行（可点击展开/收起）
          InkWell(
            onTap: () => provider.toggleRecordExpansion(index),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: isExpanded
                  ? BoxDecoration(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(12),
                      ),
                      gradient: LinearGradient(
                        colors: [
                          Theme.of(context).brightness == Brightness.dark
                              ? Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.2)
                              : Theme.of(
                                  context,
                                ).primaryColor.withValues(alpha: 0.1),
                          Theme.of(context).brightness == Brightness.dark
                              ? Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.1)
                              : Theme.of(
                                  context,
                                ).primaryColor.withValues(alpha: 0.05),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    )
                  : null,
              child: Row(
                children: [
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: isExpanded
                        ? (Theme.of(context).brightness == Brightness.dark
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).primaryColor)
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          record.courseNameCn,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isExpanded
                                ? FontWeight.bold
                                : FontWeight.w500,
                          ),
                        ),
                        if (isExpanded && record.courseNameEn.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            record.courseNameEn,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildScoreBadge(record.score),
                ],
              ),
            ),
          ),
          // 展开的详细信息
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _buildInfoRow('课程代码', record.courseCode),
                  const SizedBox(height: 8),
                  _buildInfoRow('课程班级', record.courseClass),
                  const SizedBox(height: 8),
                  _buildInfoRow('学分', record.credits),
                  const SizedBox(height: 8),
                  _buildInfoRow('学时', '${record.hours}'),
                  if (record.courseType != null &&
                      record.courseType!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _buildInfoRow('课程性质', record.courseType!),
                  ],
                  if (record.examType != null &&
                      record.examType!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _buildInfoRow('考试性质', record.examType!),
                  ],
                  if (record.makeupScore != null &&
                      record.makeupScore!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _buildInfoRow(
                      '补考成绩',
                      record.makeupScore!,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.orange.shade300
                          : Colors.orange,
                    ),
                  ],
                  if (record.retakeScore != null &&
                      record.retakeScore!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _buildInfoRow(
                      '重修成绩',
                      record.retakeScore!,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.blue.shade300
                          : Colors.blue,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 构建成绩徽章
  Widget _buildScoreBadge(String score) {
    // 根据成绩确定颜色
    MaterialColor? materialColor;
    Color? singleColor;
    double? numericScore = double.tryParse(score);

    if (numericScore != null) {
      // 数字成绩：60分以下一个颜色，60分之后每5分一个颜色
      if (numericScore < 60) {
        materialColor = Colors.red; // 不及格：红色
      } else if (numericScore < 65) {
        materialColor = Colors.orange; // 60-64：橙色
      } else if (numericScore < 70) {
        materialColor = Colors.amber; // 65-69：琥珀色
      } else if (numericScore < 75) {
        singleColor = Colors.yellow.shade700; // 70-74：黄色
      } else if (numericScore < 80) {
        materialColor = Colors.lightGreen; // 75-79：浅绿色
      } else if (numericScore < 85) {
        materialColor = Colors.green; // 80-84：绿色
      } else if (numericScore < 90) {
        materialColor = Colors.teal; // 85-89：青色
      } else if (numericScore < 95) {
        materialColor = Colors.blue; // 90-94：蓝色
      } else {
        materialColor = Colors.purple; // 95-100：紫色
      }
    } else {
      // 等级成绩
      if (score == '优秀') {
        materialColor = Colors.purple;
      } else if (score == '良好') {
        materialColor = Colors.blue;
      } else if (score == '中等') {
        materialColor = Colors.green;
      } else if (score == '及格') {
        materialColor = Colors.orange;
      } else {
        materialColor = Colors.red; // 不及格
      }
    }

    // 深色模式下使用更亮的颜色
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color displayColor;
    final Color bgColor;

    if (materialColor != null) {
      displayColor = isDark ? materialColor.shade300 : materialColor;
      bgColor = isDark
          ? materialColor.withValues(alpha: 0.3)
          : materialColor.withValues(alpha: 0.2);
    } else {
      // singleColor (yellow.shade700)
      displayColor = singleColor!;
      bgColor = isDark
          ? singleColor.withValues(alpha: 0.3)
          : singleColor.withValues(alpha: 0.2);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        score,
        style: TextStyle(
          color: displayColor,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    );
  }

  /// 构建信息行（键值对，左右布局）
  Widget _buildInfoRow(String label, String value, {Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
