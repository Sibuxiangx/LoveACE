import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/academic_provider.dart';
import '../providers/pinned_features_provider.dart';
import '../providers/more_provider.dart';
import '../widgets/adaptive_sliver_app_bar.dart';
import '../widgets/glass_card.dart';
import '../widgets/retryable_error_dialog.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_indicator.dart';

/// 学术信息页面
///
/// 显示学生的学业信息和培养方案信息
/// 支持自动加载、手动刷新和下拉刷新
/// 满足需求: 1.1, 1.2, 1.3, 1.4, 1.5, 12.1, 12.2, 12.3, 12.4, 12.5
class AcademicPage extends StatefulWidget {
  const AcademicPage({super.key});

  @override
  State<AcademicPage> createState() => _AcademicPageState();
}

class _AcademicPageState extends State<AcademicPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    final provider = Provider.of<AcademicProvider>(context, listen: false);
    await provider.loadData(forceRefresh: forceRefresh);

    if (mounted && provider.state == AcademicState.error) {
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

  /// 显示固定功能管理对话框
  void _showPinDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const _PinManagementDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Consumer<AcademicProvider>(
        builder: (context, provider, child) {
          if (provider.state == AcademicState.loading) {
            return CustomScrollView(
              slivers: [
                AdaptiveSliverAppBar(
                  title: '学术信息',
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _refreshData,
                      tooltip: '刷新',
                    ),
                  ],
                ),
                const SliverLoadingIndicator(message: '正在加载学术信息...'),
              ],
            );
          }

          if (provider.state == AcademicState.loaded) {
            return RefreshIndicator(
              onRefresh: _refreshData,
              child: CustomScrollView(
                slivers: [
                  AdaptiveSliverAppBar(
                    title: '学术信息',
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.push_pin_outlined),
                        onPressed: () => _showPinDialog(context),
                        tooltip: '管理固定功能',
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
                        _buildAcademicInfoCard(context, provider),
                        const SizedBox(height: 16),
                        _buildTrainingPlanCard(context, provider),
                        const SizedBox(height: 16),
                        _buildPinnedFeaturesCard(context),
                      ]),
                    ),
                  ),
                ],
              ),
            );
          }

          if (provider.state == AcademicState.error) {
            return CustomScrollView(
              slivers: [
                AdaptiveSliverAppBar(
                  title: '学术信息',
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

          return CustomScrollView(
            slivers: [
              AdaptiveSliverAppBar(
                title: '学术信息',
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

  /// 构建固定功能卡片
  Widget _buildPinnedFeaturesCard(BuildContext context) {
    return Consumer2<PinnedFeaturesProvider, MoreProvider>(
      builder: (context, pinnedProvider, moreProvider, child) {
        if (pinnedProvider.pinnedCount == 0) {
          return GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Icon(
                  Icons.push_pin_outlined,
                  size: 48,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 12),
                Text(
                  '暂无固定功能',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '点击右上角图钉按钮，从更多功能中选择最多 3 个功能固定到首页',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        }

        final pinnedFeatures = moreProvider.features
            .where((f) => pinnedProvider.isPinned(f.id))
            .toList();

        return GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.push_pin,
                    size: 20,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).primaryColor,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '快捷功能',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...pinnedFeatures.map((feature) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () {
                      moreProvider.navigateToFeature(context, feature.id);
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            feature.icon,
                            size: 24,
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).primaryColor,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  feature.title,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  feature.description,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  /// 构建学业信息卡片
  Widget _buildAcademicInfoCard(
    BuildContext context,
    AcademicProvider provider,
  ) {
    final info = provider.academicInfo!;

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '学业信息',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildInfoRow(context, '当前学期', info.currentTermName),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildCompactInfo(
                  context,
                  '已修',
                  '${info.completedCourses}',
                  '门',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildCompactInfo(
                  context,
                  '不及格',
                  '${info.failedCourses}',
                  '门',
                  valueColor: info.failedCourses > 0
                      ? (Theme.of(context).brightness == Brightness.dark
                            ? Colors.red.shade300
                            : Colors.red)
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildCompactInfo(
                  context,
                  '待修',
                  '${info.pendingCourses}',
                  '门',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildInfoRow(context, '平均绩点', info.gpa.toStringAsFixed(2)),
        ],
      ),
    );
  }

  /// 构建培养方案卡片
  Widget _buildTrainingPlanCard(
    BuildContext context,
    AcademicProvider provider,
  ) {
    final info = provider.trainingPlanInfo!;

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '培养方案',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildPlanInfoRow(context, '年级', '${info.grade}级'),
          const SizedBox(height: 8),
          _buildPlanInfoRow(context, '专业', info.majorName),
          const SizedBox(height: 8),
          _buildPlanInfoRow(context, '方案', info.planName),
        ],
      ),
    );
  }

  /// 构建信息行
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
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  /// 构建培养方案信息行
  Widget _buildPlanInfoRow(BuildContext context, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 48,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  /// 构建紧凑信息块
  Widget _buildCompactInfo(
    BuildContext context,
    String label,
    String value,
    String unit, {
    Color? valueColor,
  }) {
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
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color:
                        valueColor ?? Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                TextSpan(
                  text: ' $unit',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 固定功能管理对话框
class _PinManagementDialog extends StatelessWidget {
  const _PinManagementDialog();

  @override
  Widget build(BuildContext context) {
    return Consumer2<PinnedFeaturesProvider, MoreProvider>(
      builder: (context, pinnedProvider, moreProvider, child) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.push_pin,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).primaryColor,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '管理固定功能',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: '关闭',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '已固定 ${pinnedProvider.pinnedCount}/${PinnedFeaturesProvider.maxPinnedCount} 个功能',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: moreProvider.features.map((feature) {
                        final isPinned = pinnedProvider.isPinned(feature.id);
                        final canPin = pinnedProvider.canPinMore || isPinned;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: InkWell(
                            onTap: canPin
                                ? () async {
                                    final success = await pinnedProvider
                                        .togglePin(feature.id);
                                    if (!success &&
                                        !isPinned &&
                                        context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            '最多只能固定 ${PinnedFeaturesProvider.maxPinnedCount} 个功能',
                                          ),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    }
                                  }
                                : null,
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isPinned
                                      ? (Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.primary
                                            : Theme.of(context).primaryColor)
                                      : Theme.of(
                                          context,
                                        ).colorScheme.outlineVariant,
                                  width: isPinned ? 2 : 1.5,
                                ),
                                color: isPinned
                                    ? (Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? Theme.of(context)
                                                .colorScheme
                                                .primary
                                                .withValues(alpha: 0.15)
                                          : Theme.of(context).primaryColor
                                                .withValues(alpha: 0.08))
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    feature.icon,
                                    size: 24,
                                    color: !canPin
                                        ? Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant
                                              .withValues(alpha: 0.3)
                                        : (Theme.of(context).brightness ==
                                                  Brightness.dark
                                              ? Theme.of(
                                                  context,
                                                ).colorScheme.primary
                                              : Theme.of(context).primaryColor),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          feature.title,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: !canPin
                                                ? Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant
                                                      .withValues(alpha: 0.5)
                                                : null,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          feature.description,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant
                                                    .withValues(
                                                      alpha: !canPin
                                                          ? 0.3
                                                          : 1.0,
                                                    ),
                                              ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    isPinned
                                        ? Icons.push_pin
                                        : Icons.push_pin_outlined,
                                    color: !canPin
                                        ? Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant
                                              .withValues(alpha: 0.3)
                                        : (isPinned
                                              ? (Theme.of(context).brightness ==
                                                        Brightness.dark
                                                    ? Theme.of(
                                                        context,
                                                      ).colorScheme.primary
                                                    : Theme.of(
                                                        context,
                                                      ).primaryColor)
                                              : Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (pinnedProvider.pinnedCount > 0) ...[
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await pinnedProvider.clearAll();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('已清除所有固定功能'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.clear_all),
                      label: const Text('清除所有'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
