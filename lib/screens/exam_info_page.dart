import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/exam_provider.dart';
import '../providers/theme_provider.dart';
import '../models/jwc/exam_info.dart';
import '../widgets/adaptive_sliver_app_bar.dart';
import '../widgets/glass_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/retryable_error_dialog.dart';
import '../widgets/loading_indicator.dart';
import '../widgets/app_background.dart';

/// 考试信息页面
///
/// 提供考试信息查询功能
/// 支持自动加载、手动刷新和下拉刷新
class ExamInfoPage extends StatefulWidget {
  const ExamInfoPage({super.key});

  @override
  State<ExamInfoPage> createState() => _ExamInfoPageState();
}

class _ExamInfoPageState extends State<ExamInfoPage> {
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
    showDialog(
      context: context,
      builder: (context) => RetryableErrorDialog(
        message: message,
        retryable: retryable,
        onRetry: _loadData,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final hasBackground = themeProvider.backgroundPath != null;

    return Scaffold(
      backgroundColor: hasBackground ? Colors.transparent : null,
      body: AppBackground(
        child: Consumer<ExamProvider>(
          builder: (context, provider, child) {
          // 加载中状态
          if (provider.state == ExamState.loading) {
            return CustomScrollView(
              slivers: [
                AdaptiveSliverAppBar(
                  title: '考试信息',
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _refreshData,
                      tooltip: '刷新',
                    ),
                  ],
                ),
                const SliverLoadingIndicator(message: '正在加载考试信息...'),
              ],
            );
          }

          // 加载完成状态
          if (provider.state == ExamState.loaded) {
            // 检查是否有考试数据
            if (provider.exams.isEmpty) {
              return CustomScrollView(
                slivers: [
                  AdaptiveSliverAppBar(
                    title: '考试信息',
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: _refreshData,
                        tooltip: '刷新',
                      ),
                    ],
                  ),
                  SliverFillRemaining(
                    child: EmptyState.noExams(
                      title: '暂时无考试',
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
                    title: '考试信息',
                    actions: [
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
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          return _buildExamCard(context, provider.exams[index]);
                        },
                        childCount: provider.exams.length,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          // 错误状态
          if (provider.state == ExamState.error) {
            return CustomScrollView(
              slivers: [
                AdaptiveSliverAppBar(
                  title: '考试信息',
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
                title: '考试信息',
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

  Widget _buildExamCard(BuildContext context, UnifiedExamInfo exam) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行：考试类型标签 + 课程名称
          Row(
            children: [
              _buildExamTypeBadge(context, exam.examType),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  exam.courseName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 考试信息行
          _buildInfoRow(context, '考试日期', exam.examDate),
          const SizedBox(height: 8),
          _buildInfoRow(context, '考试时间', exam.examTime),
          const SizedBox(height: 8),
          _buildInfoRow(context, '考试地点', exam.examLocation),

          // 座位号（如果有）
          if (exam.note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.green.withValues(alpha: 0.25)
                    : Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.event_seat,
                    size: 16,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.green.shade300
                        : Colors.green,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    exam.note,
                    style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.green.shade300
                          : Colors.green,
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

  Widget _buildExamTypeBadge(BuildContext context, String examType) {
    final isSchoolExam = examType == '校统考';
    final color = isSchoolExam ? Colors.blue : Colors.orange;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? color.withValues(alpha: 0.3)
            : color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        examType,
        style: TextStyle(
          color: Theme.of(context).brightness == Brightness.dark
              ? (isSchoolExam ? Colors.blue.shade300 : Colors.orange.shade300)
              : color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
      ],
    );
  }
}
