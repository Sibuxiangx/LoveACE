import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/term_provider.dart';
import '../models/jwc/term_item.dart';
import '../widgets/adaptive_sliver_app_bar.dart';
import '../widgets/glass_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/retryable_error_dialog.dart';
import '../widgets/loading_indicator.dart';
import 'term_score_detail_page.dart';

/// 学期列表页面
///
/// 显示所有可查询的学期列表，区分当前学期和历史学期
/// 支持自动加载、手动刷新和下拉刷新
/// 满足需求: 1.1, 1.2, 1.3, 1.4, 1.5, 7.1, 8.1, 9.1
class TermListPage extends StatefulWidget {
  const TermListPage({super.key});

  @override
  State<TermListPage> createState() => _TermListPageState();
}

class _TermListPageState extends State<TermListPage> {
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
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Consumer<TermProvider>(
        builder: (context, provider, child) {
          // 加载中状态
          if (provider.state == TermState.loading) {
            return CustomScrollView(
              slivers: [
                AdaptiveSliverAppBar(
                  title: '学期成绩',
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _refreshData,
                      tooltip: '刷新',
                    ),
                  ],
                ),
                const SliverLoadingIndicator(message: '正在加载学期列表...'),
              ],
            );
          }

          // 加载完成状态
          if (provider.state == TermState.loaded && provider.termList != null) {
            return RefreshIndicator(
              onRefresh: _refreshData,
              child: CustomScrollView(
                slivers: [
                  AdaptiveSliverAppBar(
                    title: '学期成绩',
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
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final term = provider.termList![index];
                        if (term.isCurrent) {
                          return _buildCurrentTermCard(term);
                        } else {
                          return _buildHistoricalTermCard(term);
                        }
                      }, childCount: provider.termList!.length),
                    ),
                  ),
                ],
              ),
            );
          }

          // 错误状态
          if (provider.state == TermState.error) {
            return CustomScrollView(
              slivers: [
                AdaptiveSliverAppBar(
                  title: '学期成绩',
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
                title: '学期成绩',
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
    );
  }

  /// 构建当前学期卡片
  Widget _buildCurrentTermCard(TermItem term) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(0),
      child: InkWell(
        onTap: () => _navigateToScoreDetail(term),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              colors: [
                Theme.of(context).brightness == Brightness.dark
                    ? Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.3)
                    : Theme.of(context).primaryColor.withValues(alpha: 0.15),
                Theme.of(context).brightness == Brightness.dark
                    ? Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.15)
                    : Theme.of(context).primaryColor.withValues(alpha: 0.05),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).primaryColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.star,
                          size: 14,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.black
                              : Colors.white,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '当前学期',
                          style: TextStyle(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? Colors.black
                                : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                term.termName,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.arrow_forward,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '点击查看成绩详情',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建历史学期卡片
  Widget _buildHistoricalTermCard(TermItem term) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(0),
      child: InkWell(
        onTap: () => _navigateToScoreDetail(term),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                Icons.calendar_today,
                size: 20,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  term.termName,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 导航到成绩详情页
  void _navigateToScoreDetail(TermItem term) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TermScoreDetailPage(
          termCode: term.termCode,
          termName: term.termName,
        ),
      ),
    );
  }
}
