import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/competition_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/adaptive_sliver_app_bar.dart';
import '../widgets/retryable_error_dialog.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_indicator.dart';
import '../widgets/glass_card.dart';
import '../widgets/app_background.dart';
import '../models/competition/competition_full_response.dart';
import '../models/competition/award_project.dart';

/// 学科竞赛信息页面
///
/// 显示学生的获奖项目信息和学分汇总
/// 支持自动加载、手动刷新和下拉刷新
/// 满足需求: 7.1, 7.2, 7.3, 7.4, 7.5, 10.1, 10.2, 10.3, 10.4, 10.5, 12.1, 12.2, 12.3, 12.4, 12.5, 15.1, 15.2, 15.3, 15.4, 15.5
class CompetitionPage extends StatefulWidget {
  const CompetitionPage({super.key});

  @override
  State<CompetitionPage> createState() => _CompetitionPageState();
}

class _CompetitionPageState extends State<CompetitionPage> {
  @override
  void initState() {
    super.initState();
    // 页面初始化后自动加载数据（优先使用缓存）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  /// 加载竞赛数据
  ///
  /// [forceRefresh] 是否强制刷新（清除缓存）
  Future<void> _loadData({bool forceRefresh = false}) async {
    final provider = Provider.of<CompetitionProvider>(context, listen: false);
    await provider.loadData(forceRefresh: forceRefresh);

    // 如果加载失败，显示错误对话框
    if (mounted && provider.state == CompetitionState.error) {
      _showErrorDialog(
        provider.errorMessage ?? '加载失败',
        provider.isRetryable,
      );
    }
  }

  /// 刷新数据（强制从网络加载）
  Future<void> _refreshData() async {
    await _loadData(forceRefresh: true);
  }

  /// 显示错误对话框
  ///
  /// [message] 错误消息
  /// [retryable] 是否可重试
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
        child: Consumer<CompetitionProvider>(
          builder: (context, provider, child) {
          // 加载中状态
          if (provider.state == CompetitionState.loading) {
            return CustomScrollView(
              slivers: [
                AdaptiveSliverAppBar(
                  title: '学科竞赛',
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _refreshData,
                      tooltip: '刷新',
                    ),
                  ],
                ),
                const SliverLoadingIndicator(message: '正在加载竞赛信息...'),
              ],
            );
          }

          // 加载完成状态
          if (provider.state == CompetitionState.loaded) {
            final info = provider.competitionInfo;

            // 数据为空的情况
            if (info == null || info.awards.isEmpty) {
              return CustomScrollView(
                slivers: [
                  AdaptiveSliverAppBar(
                    title: '学科竞赛',
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
                      title: '暂无获奖项目',
                      description: '您还没有申报任何获奖项目',
                      actionText: '刷新',
                      onAction: _refreshData,
                    ),
                  ),
                ],
              );
            }

            // 有数据的情况
            return RefreshIndicator(
              onRefresh: _refreshData,
              child: CustomScrollView(
                slivers: [
                  AdaptiveSliverAppBar(
                    title: '学科竞赛',
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
                          // 第一个元素：学分汇总卡片
                          if (index == 0) {
                            return Column(
                              children: [
                                _buildCreditsSummaryCard(info),
                                const SizedBox(height: 16),
                              ],
                            );
                          }
                          
                          // 后续元素：获奖项目卡片
                          final awardIndex = index - 1;
                          if (awardIndex < info.awards.length) {
                            return _buildAwardProjectCard(info.awards[awardIndex]);
                          }
                          
                          return null;
                        },
                        childCount: info.awards.length + 1, // 学分汇总卡片 + 获奖项目列表
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          // 错误状态
          if (provider.state == CompetitionState.error) {
            return CustomScrollView(
              slivers: [
                AdaptiveSliverAppBar(
                  title: '学科竞赛',
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
                title: '学科竞赛',
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

  /// 构建学分汇总卡片
  ///
  /// 显示学生ID、总学分和各类学分的详细信息
  /// 满足需求: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8, 3.9, 11.1, 11.2, 11.3, 16.1, 16.2, 16.3, 16.4, 16.5
  Widget _buildCreditsSummaryCard(CompetitionFullResponse info) {
    final summary = info.creditsSummary;
    
    // 如果没有学分汇总数据，返回空容器
    if (summary == null) {
      return const SizedBox.shrink();
    }

    return GlassCard(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Text(
            '学分汇总',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),

          // 学生ID
          Text(
            '学生ID: ${info.studentId}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),

          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),

          // 总学分（居中显示，突出显示）
          Center(
            child: Column(
              children: [
                Text(
                  '总学分',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${summary.totalCredits.toStringAsFixed(2)} 学分',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).primaryColor,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),

          // 各类学分详情
          _buildInfoRow(
            context,
            '学科竞赛学分',
            summary.formatCredit(summary.disciplineCompetitionCredits),
          ),
          const SizedBox(height: 8),
          _buildInfoRow(
            context,
            '科研项目学分',
            summary.formatCredit(summary.scientificResearchCredits),
          ),
          const SizedBox(height: 8),
          _buildInfoRow(
            context,
            '可转竞赛类学分',
            summary.formatCredit(summary.transferableCompetitionCredits),
          ),
          const SizedBox(height: 8),
          _buildInfoRow(
            context,
            '创新创业实践学分',
            summary.formatCredit(summary.innovationPracticeCredits),
          ),
          const SizedBox(height: 8),
          _buildInfoRow(
            context,
            '能力资格认证学分',
            summary.formatCredit(summary.abilityCertificationCredits),
          ),
          const SizedBox(height: 8),
          _buildInfoRow(
            context,
            '其他项目学分',
            summary.formatCredit(summary.otherProjectCredits),
          ),
        ],
      ),
    );
  }

  /// 构建信息行（键值对，左右布局）
  ///
  /// [label] 标签文字
  /// [value] 值文字
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
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  /// 构建获奖项目卡片
  ///
  /// 显示单个获奖项目的详细信息，包括：
  /// - 项目名称和等级图标
  /// - 等级标签（国家级/省部级/校级）
  /// - 奖项等级（一等奖/二等奖等）
  /// - 获奖日期、项目主持人、顺序号、获奖学分
  /// - 奖励金额（如果大于0）
  /// - 申报状态和审核状态
  /// 
  /// 满足需求: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 4.8, 4.9, 5.1, 5.2, 5.3, 5.4, 5.5, 
  ///          6.1, 6.2, 6.3, 6.4, 6.5, 11.1, 11.2, 11.3, 11.4, 11.5, 11.6, 
  ///          18.1, 18.2, 18.3, 18.4, 18.5, 18.6
  Widget _buildAwardProjectCard(AwardProject project) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 项目名称和等级图标
          Row(
            children: [
              Icon(
                project.getLevelIcon(),
                color: project.getLevelColor(context),
                size: 24,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  project.projectName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // 等级标签和奖项等级
          Row(
            children: [
              _buildLevelBadge(project),
              const SizedBox(width: 8),
              Text(
                project.grade,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 12),

          // 项目详情
          _buildDetailRow(context, '获奖日期', project.awardDate),
          const SizedBox(height: 6),
          _buildDetailRow(context, '项目主持人', project.applicantId),
          const SizedBox(height: 6),
          _buildDetailRow(context, '顺序号', '${project.order}'),
          const SizedBox(height: 6),
          _buildDetailRow(context, '获奖学分', project.credits.toStringAsFixed(1)),

          // 奖励金额（如果大于0）
          if (project.bonus > 0) ...[
            const SizedBox(height: 6),
            _buildDetailRow(
              context,
              '奖励金额',
              '¥${project.bonus.toStringAsFixed(2)}',
            ),
          ],

          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 12),

          // 申报状态和审核状态
          Row(
            children: [
              _buildStatusChip(project),
              const SizedBox(width: 8),
              _buildVerificationChip(project),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建等级标签
  ///
  /// 显示项目等级（国家级/省部级/校级）
  /// 使用彩色背景，深色模式透明度0.3，浅色模式0.2
  /// 
  /// 满足需求: 6.1, 6.2, 6.3, 6.4, 11.1, 11.2
  Widget _buildLevelBadge(AwardProject project) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final levelColor = project.getLevelColor(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? levelColor.withValues(alpha: 0.3)
            : levelColor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        project.level,
        style: TextStyle(
          color: levelColor,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  /// 构建详情行
  ///
  /// 显示项目详细信息的键值对
  /// 
  /// [label] 标签文字
  /// [value] 值文字
  Widget _buildDetailRow(BuildContext context, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  /// 构建申报状态标签
  ///
  /// 显示项目的申报状态
  /// 
  /// 满足需求: 5.4, 18.1, 18.2, 18.3
  Widget _buildStatusChip(AwardProject project) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.blue.withValues(alpha: 0.25)
            : Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.description,
            size: 14,
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.blue.shade300
                : Colors.blue,
          ),
          const SizedBox(width: 4),
          Text(
            project.status,
            style: TextStyle(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.blue.shade300
                  : Colors.blue,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建审核状态标签
  ///
  /// 显示项目的审核状态，带图标和颜色
  /// - 通过：绿色勾选图标
  /// - 未通过：红色取消图标
  /// - 待审核：灰色时钟图标
  /// 
  /// 满足需求: 5.5, 18.4, 18.5, 18.6
  Widget _buildVerificationChip(AwardProject project) {
    final verificationColor = project.getVerificationColor(context);
    final verificationIcon = project.getVerificationIcon();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? verificationColor.withValues(alpha: 0.25)
            : verificationColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            verificationIcon,
            size: 14,
            color: verificationColor,
          ),
          const SizedBox(width: 4),
          Text(
            project.verificationStatus,
            style: TextStyle(
              color: verificationColor,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
