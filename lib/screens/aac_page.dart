import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/aac_provider.dart';
import '../widgets/adaptive_sliver_app_bar.dart';
import '../widgets/glass_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/retryable_error_dialog.dart';
import '../widgets/loading_indicator.dart';
import '../widgets/export_confirm_dialog.dart';
import '../models/aac/aac_credit_info.dart';
import '../services/logger_service.dart';

class AACPage extends StatefulWidget {
  const AACPage({super.key});

  @override
  State<AACPage> createState() => _AACPageState();
}

class _AACPageState extends State<AACPage> {
  // 记录每个分类的展开状态
  final Map<String, bool> _expandedCategories = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 每次进入页面都尝试加载数据（会优先使用缓存）
      _loadData();
    });
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    final provider = Provider.of<AACProvider>(context, listen: false);
    await provider.loadData(forceRefresh: forceRefresh);

    if (mounted && provider.state == AACState.error) {
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

  /// 导出CSV
  Future<void> _exportCSV() async {
    await ExportConfirmDialog.show(
      context,
      title: '导出爱安财分数',
      content: '确认导出爱安财详细分数为CSV文件？',
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

          final provider = Provider.of<AACProvider>(context, listen: false);
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
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Consumer<AACProvider>(
        builder: (context, provider, child) {
          if (provider.state == AACState.loading) {
            return CustomScrollView(
              slivers: [
                AdaptiveSliverAppBar(
                  title: '爱安财',
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _refreshData,
                      tooltip: '刷新',
                    ),
                  ],
                ),
                const SliverLoadingIndicator(message: '正在加载爱安财数据...'),
              ],
            );
          }

          if (provider.state == AACState.loaded &&
              provider.creditInfo != null &&
              provider.creditList != null) {
            return RefreshIndicator(
              onRefresh: _refreshData,
              child: CustomScrollView(
                slivers: [
                  AdaptiveSliverAppBar(
                    title: '爱安财',
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
                        _buildCreditInfoCard(
                          provider.creditInfo!,
                          provider.creditList!,
                        ),
                        const SizedBox(height: 16),
                        ...provider.creditList!.map(
                          (category) => _buildCategoryCard(category),
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
            );
          }

          if (provider.state == AACState.error) {
            return CustomScrollView(
              slivers: [
                AdaptiveSliverAppBar(
                  title: '爱安财',
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
                title: '爱安财',
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

  Widget _buildCreditInfoCard(
    AACCreditInfo info,
    List<AACCreditCategory> categories,
  ) {
    // 计算社会实践分数
    double practiceScore = 0.0;
    for (final category in categories) {
      if (category.typeName.contains('劳动教育') ||
          category.typeName.contains('让逸竞劳')) {
        for (final item in category.children) {
          if (item.typeName.contains('三下乡') ||
              item.title.contains('三下乡') ||
              item.title.contains('社会实践')) {
            practiceScore += item.score;
          }
        }
      }
    }

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '爱安财总分',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '共 ${categories.length} 个分类',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? (info.isTypeAdopt
                            ? Colors.green.withValues(alpha: 0.3)
                            : Colors.orange.withValues(alpha: 0.3))
                      : (info.isTypeAdopt
                            ? Colors.green.withValues(alpha: 0.2)
                            : Colors.orange.withValues(alpha: 0.2)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      info.isTypeAdopt ? Icons.check_circle : Icons.cancel,
                      size: 14,
                      color: info.isTypeAdopt ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      info.isTypeAdopt ? '已达标' : '未达标',
                      style: TextStyle(
                        color: info.isTypeAdopt ? Colors.green : Colors.orange,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: info.totalScore.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).primaryColor,
                      ),
                    ),
                    if (practiceScore > 0) ...[
                      TextSpan(
                        text: ' + ',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).primaryColor,
                        ),
                      ),
                      TextSpan(
                        text: practiceScore.toStringAsFixed(1),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.8)
                              : Theme.of(
                                  context,
                                ).primaryColor.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                    TextSpan(
                      text: ' 分',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (practiceScore > 0 ||
              (!info.isTypeAdopt && info.typeAdoptResult.isNotEmpty)) ...[
            const SizedBox(height: 10),
            if (practiceScore > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.blue.withValues(alpha: 0.25)
                      : Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.volunteer_activism,
                      size: 12,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.blue.shade300
                          : Colors.blue,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '含社会实践 +${practiceScore.toStringAsFixed(1)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.blue.shade300
                            : Colors.blue,
                      ),
                    ),
                  ],
                ),
              ),
            if (!info.isTypeAdopt && info.typeAdoptResult.isNotEmpty) ...[
              if (practiceScore > 0) const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.orange.withValues(alpha: 0.25)
                      : Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 12,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.orange.shade300
                          : Colors.orange,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        info.typeAdoptResult,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.orange.shade300
                              : Colors.orange,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildCategoryCard(AACCreditCategory category) {
    final isSocialPractice = category.typeName.contains('社会实践');
    final isExpanded = _expandedCategories[category.typeName] ?? false;

    return GlassCard(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 可点击的标题区域
          InkWell(
            onTap: () {
              setState(() {
                _expandedCategories[category.typeName] = !isExpanded;
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // 展开/收起图标
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).primaryColor,
                  ),
                  const SizedBox(width: 8),
                  // 分类图标（如果是社会实践）
                  if (isSocialPractice) ...[
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.blue.withValues(alpha: 0.3)
                            : Colors.blue.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.volunteer_activism,
                        size: 20,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.blue.shade300
                            : Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  // 分类名称和记录数
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          category.typeName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${category.children.length} 项记录',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  // 总分
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.25)
                          : Theme.of(
                              context,
                            ).primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${category.totalScore.toStringAsFixed(1)} 分',
                      style: TextStyle(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).primaryColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 展开的详细内容
          if (isExpanded && category.children.isNotEmpty) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: category.children
                    .map((item) => _buildCreditItem(item))
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCreditItem(AACCreditItem item) {
    final isPractice =
        item.typeName.contains('三下乡') ||
        item.title.contains('三下乡') ||
        item.title.contains('社会实践');

    Color scoreColor;
    if (item.score >= 10) {
      scoreColor = Colors.red;
    } else if (item.score >= 5) {
      scoreColor = Colors.orange;
    } else if (item.score >= 2) {
      scoreColor = Colors.blue;
    } else {
      scoreColor = Colors.green;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isPractice
              ? (Theme.of(context).brightness == Brightness.dark
                    ? Colors.blue.shade300
                    : Colors.blue)
              : Theme.of(context).colorScheme.outlineVariant,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    if (isPractice) ...[
                      Icon(
                        Icons.volunteer_activism,
                        size: 16,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.blue.shade300
                            : Colors.blue,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? scoreColor.withValues(alpha: 0.25)
                      : scoreColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '+${item.score.toStringAsFixed(1)}',
                  style: TextStyle(
                    color: scoreColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          if (item.typeName.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              item.typeName,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (item.addTime.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.access_time,
                  size: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  item.addTime,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
