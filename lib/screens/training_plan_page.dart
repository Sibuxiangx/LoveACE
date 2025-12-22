import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/training_plan_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/adaptive_sliver_app_bar.dart';
import '../widgets/retryable_error_dialog.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_indicator.dart';
import '../widgets/glass_card.dart';
import '../widgets/app_background.dart';
import '../widgets/export_confirm_dialog.dart';
import '../models/jwc/plan_completion_info.dart';
import '../models/jwc/plan_category.dart';
import '../models/jwc/plan_course.dart';
import '../models/jwc/plan_option.dart';
import '../services/logger_service.dart';

/// 培养方案完成情况页面
///
/// 显示学生的培养方案完成进度，包括各类课程的完成情况、学分统计、预估毕业学分等信息
/// 支持自动加载、手动刷新和下拉刷新
/// 满足需求: 9.1, 9.4, 13.1, 13.2, 18.3
class TrainingPlanPage extends StatefulWidget {
  const TrainingPlanPage({super.key});

  @override
  State<TrainingPlanPage> createState() => _TrainingPlanPageState();
}

class _TrainingPlanPageState extends State<TrainingPlanPage> {
  // 记录每个分类的展开状态
  final Map<String, bool> _expandedCategories = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  /// 加载培养方案数据
  ///
  /// forceRefresh: 是否强制刷新（清除缓存）
  Future<void> _loadData({bool forceRefresh = false}) async {
    final provider = Provider.of<TrainingPlanProvider>(context, listen: false);
    await provider.loadData(forceRefresh: forceRefresh);

    if (mounted && provider.state == TrainingPlanState.error) {
      _showErrorDialog(provider.errorMessage ?? '加载失败', provider.isRetryable);
    }
  }

  /// 刷新数据（强制从网络加载）
  Future<void> _refreshData() async {
    await _loadData(forceRefresh: true);
  }

  /// 显示错误对话框
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
    final provider = Provider.of<TrainingPlanProvider>(context, listen: false);
    
    // 如果是多培养方案用户，显示选择对话框
    if (provider.hasMultiplePlans && provider.planOptions.isNotEmpty) {
      await _showExportPlanSelectionDialog(provider);
      return;
    }
    
    // 单培养方案用户，直接导出
    await _performExport(null);
  }

  /// 显示导出培养方案选择对话框
  Future<void> _showExportPlanSelectionDialog(TrainingPlanProvider provider) async {
    final selectedPlanId = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择要导出的培养方案'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: provider.planOptions.map((option) {
              final isCurrent = option.planId == provider.selectedPlanId;
              return ListTile(
                leading: Icon(
                  option.planType == '主修' ? Icons.school : Icons.menu_book,
                  color: option.planType == '主修'
                      ? (Theme.of(context).brightness == Brightness.dark
                            ? Colors.green.shade300
                            : Colors.green)
                      : (Theme.of(context).brightness == Brightness.dark
                            ? Colors.blue.shade300
                            : Colors.blue),
                ),
                title: Text(option.planName),
                subtitle: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: (option.planType == '主修' ? Colors.green : Colors.blue)
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        option.planType,
                        style: TextStyle(
                          fontSize: 11,
                          color: option.planType == '主修' ? Colors.green : Colors.blue,
                        ),
                      ),
                    ),
                    if (isCurrent) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '当前查看',
                          style: TextStyle(fontSize: 11, color: Colors.orange),
                        ),
                      ),
                    ],
                  ],
                ),
                onTap: () => Navigator.of(context).pop(option.planId),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );

    if (selectedPlanId != null) {
      await _performExport(selectedPlanId);
    }
  }

  /// 执行导出操作
  Future<void> _performExport(String? planId) async {
    await ExportConfirmDialog.show(
      context,
      title: '导出培养方案',
      content: '确认导出培养方案完成情况为CSV文件？',
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

          final provider = Provider.of<TrainingPlanProvider>(
            context,
            listen: false,
          );
          
          if (planId != null) {
            await provider.exportPlanToCSV(planId);
          } else {
            await provider.exportToCSV();
          }

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

  /// 显示预估毕业学分说明对话框
  void _showGraduationCreditsInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.info_outline,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.blue.shade300
                  : Colors.blue,
            ),
            const SizedBox(width: 8),
            const Text('预估毕业学分说明'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 计算方法
              Text(
                '计算方法',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '预估毕业学分 = 所有最小分类（叶子分类节点）的最低修读学分之和',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.blue.withValues(alpha: 0.15)
                      : Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.blue.shade700
                        : Colors.blue.shade200,
                  ),
                ),
                child: Text(
                  '例如：\n'
                  '• 思想政治理论（最低17学分）\n'
                  '• 外语必修课程（最低4学分）\n'
                  '• 外语基础课程群（最低2学分）\n'
                  '...\n'
                  '预估毕业学分 = 17 + 4 + 2 + ...',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.blue.shade200
                        : Colors.blue.shade900,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 重要提示
              Text(
                '重要提示',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.orange.shade300
                      : Colors.orange,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.orange.withValues(alpha: 0.15)
                      : Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.orange.shade700
                        : Colors.orange.shade200,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 20,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.orange.shade300
                              : Colors.orange,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '此数值仅供参考，非精确值',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color:
                                      Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.orange.shade300
                                      : Colors.orange.shade900,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '由于培养方案在学习过程中可能会调整和变动，实际毕业所需学分可能与此预估值有所差异。请以学校教务系统的最新要求为准。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.orange.shade200
                            : Colors.orange.shade900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
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
        child: Consumer<TrainingPlanProvider>(
          builder: (context, provider, child) {
            // 加载中状态
            if (provider.state == TrainingPlanState.loading) {
              return CustomScrollView(
                slivers: [
                  AdaptiveSliverAppBar(
                    title: '培养方案完成情况',
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: _refreshData,
                        tooltip: '刷新',
                      ),
                    ],
                  ),
                  const SliverLoadingIndicator(message: '正在加载培养方案...'),
                ],
              );
            }

            // 需要选择培养方案状态（多培养方案用户）
            if (provider.state == TrainingPlanState.needSelection) {
              return _buildPlanSelectionView(provider);
            }

            // 加载完成状态
            if (provider.state == TrainingPlanState.loaded) {
              final planInfo = provider.planInfo;

              // 检查数据是否为空
              if (planInfo == null || planInfo.categories.isEmpty) {
                return CustomScrollView(
                  slivers: [
                    AdaptiveSliverAppBar(
                      title: '培养方案完成情况',
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
                        title: '暂无培养方案数据',
                        description: '点击右上角刷新按钮加载数据',
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
                      title: '培养方案完成情况',
                      actions: [
                        // 如果是多培养方案用户，显示切换按钮
                        if (provider.hasMultiplePlans)
                          IconButton(
                            icon: const Icon(Icons.swap_horiz),
                            onPressed: () => provider.backToSelection(),
                            tooltip: '切换培养方案',
                          ),
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
                          _buildSummaryCard(planInfo),
                          const SizedBox(height: 16),
                          // 分类列表
                          ...planInfo.categories.map(
                            (category) => _buildCategoryCard(category),
                          ),
                        ]),
                      ),
                    ),
                  ],
                ),
              );
            }

            // 错误状态
            if (provider.state == TrainingPlanState.error) {
              return CustomScrollView(
                slivers: [
                  AdaptiveSliverAppBar(
                    title: '培养方案完成情况',
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
                  title: '培养方案完成情况',
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

  /// 构建培养方案选择视图（多培养方案用户）
  Widget _buildPlanSelectionView(TrainingPlanProvider provider) {
    final options = provider.planOptions;
    final hint = provider.planSelectionResponse?.hint;

    return CustomScrollView(
      slivers: [
        AdaptiveSliverAppBar(
          title: '选择培养方案',
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
            delegate: SliverChildListDelegate([
              // 提示信息
              if (hint != null && hint.isNotEmpty)
                GlassCard(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.blue.shade300
                            : Colors.blue,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          hint,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),

              // 说明文字
              GlassCard(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.school,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).primaryColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '您有多个培养方案',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '请选择要查看的培养方案完成情况',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

              // 培养方案选项列表
              ...options.map((option) => _buildPlanOptionCard(option, provider)),
            ]),
          ),
        ),
      ],
    );
  }

  /// 构建培养方案选项卡片
  Widget _buildPlanOptionCard(PlanOption option, TrainingPlanProvider provider) {
    final isCurrent = option.isCurrent;
    final planType = option.planType;

    // 根据方案类型选择颜色
    Color typeColor;
    if (planType == '主修') {
      typeColor = Theme.of(context).brightness == Brightness.dark
          ? Colors.green.shade300
          : Colors.green;
    } else if (planType == '辅修') {
      typeColor = Theme.of(context).brightness == Brightness.dark
          ? Colors.blue.shade300
          : Colors.blue;
    } else {
      typeColor = Theme.of(context).brightness == Brightness.dark
          ? Colors.purple.shade300
          : Colors.purple;
    }

    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(0),
      child: InkWell(
        onTap: () => provider.selectPlan(option.planId),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // 方案类型图标
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  planType == '主修' ? Icons.school : Icons.menu_book,
                  color: typeColor,
                ),
              ),
              const SizedBox(width: 16),

              // 方案信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.planName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        // 方案类型标签
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: typeColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            planType,
                            style: TextStyle(
                              fontSize: 12,
                              color: typeColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (isCurrent) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context).brightness == Brightness.dark
                                  ? Colors.green.withValues(alpha: 0.25)
                                  : Colors.green.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '当前使用',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).brightness == Brightness.dark
                                    ? Colors.green.shade300
                                    : Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // 箭头
              Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建总体信息卡片
  ///
  /// 显示培养方案名称、专业、年级、预估毕业学分和课程统计
  /// 满足需求: 2.1, 2.2, 2.3, 2.4, 2.5, 3.1, 3.2, 3.3, 12.1, 12.2, 12.3
  Widget _buildSummaryCard(PlanCompletionInfo info) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 培养方案名称
          Text(
            info.planName,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          // 专业和年级信息芯片
          Row(
            children: [
              _buildInfoChip('专业', info.major),
              const SizedBox(width: 8),
              _buildInfoChip('年级', info.grade),
            ],
          ),

          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),

          // 预估毕业学分（突出显示）
          Center(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '预估毕业学分',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 4),
                    // 问号按钮
                    InkWell(
                      onTap: _showGraduationCreditsInfo,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.help_outline,
                          size: 18,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${info.estimatedGraduationCredits.toStringAsFixed(1)} 学分',
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

          // 课程统计
          Row(
            children: [
              Expanded(
                child: _buildCompactInfo(
                  context,
                  '总分类',
                  '${info.totalCategories}',
                  '个',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildCompactInfo(
                  context,
                  '总课程',
                  '${info.totalCourses}',
                  '门',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildCompactInfo(
                  context,
                  '已过',
                  '${info.passedCourses}',
                  '门',
                  valueColor: Theme.of(context).brightness == Brightness.dark
                      ? Colors.green.shade300
                      : Colors.green,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildCompactInfo(
                  context,
                  '未过',
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
                  '未修读',
                  '${info.unreadCourses}',
                  '门',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建紧凑信息块
  ///
  /// 创建带边框的容器，显示标签、数值和单位
  /// 支持自定义数值颜色
  /// 满足需求: 2.4, 12.1
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

  /// 构建信息芯片
  ///
  /// 创建圆角容器，半透明蓝色背景，显示标签和值
  /// 适配深色模式
  /// 满足需求: 2.2, 12.3
  Widget _buildInfoChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.blue.withValues(alpha: 0.25)
            : Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.blue.shade300
                  : Colors.blue,
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.blue.shade300
                  : Colors.blue,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建分类卡片
  ///
  /// 显示分类信息，支持展开/折叠查看子分类和课程
  /// 满足需求: 4.1, 4.2, 5.1, 5.2, 5.3, 7.1, 7.2, 7.3, 7.4, 7.5, 16.1-16.5, 12.3
  Widget _buildCategoryCard(PlanCategory category, {int indent = 0}) {
    final isExpanded = _expandedCategories[category.categoryId] ?? false;

    return GlassCard(
      margin: EdgeInsets.only(bottom: 12, left: indent * 16.0),
      padding: const EdgeInsets.all(0),
      child: Column(
        children: [
          // 可点击的标题区域
          InkWell(
            onTap: () {
              setState(() {
                _expandedCategories[category.categoryId] = !isExpanded;
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题行
                  Row(
                    children: [
                      Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).primaryColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          category.categoryName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      // 达标标签
                      if (category.isCompleted)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? Colors.green.withValues(alpha: 0.3)
                                : Colors.green.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.check_circle,
                                size: 14,
                                color:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.green.shade300
                                    : Colors.green,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '已达标',
                                style: TextStyle(
                                  color:
                                      Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.green.shade300
                                      : Colors.green,
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

                  // 学分信息
                  Row(
                    children: [
                      Text(
                        '最低学分: ',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        category.minCredits.toStringAsFixed(1),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        '通过学分: ',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        category.completedCredits.toStringAsFixed(1),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _getProgressColor(
                            category.completionPercentage,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // 进度条
                  if (category.minCredits > 0) ...[
                    Row(
                      children: [
                        Expanded(
                          child: LinearProgressIndicator(
                            value: (category.completionPercentage / 100).clamp(
                              0.0,
                              1.0,
                            ),
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _getProgressColor(category.completionPercentage),
                            ),
                            minHeight: 8,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${category.completionPercentage.toStringAsFixed(1)}%',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: _getProgressColor(
                                  category.completionPercentage,
                                ),
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],

                  // 课程统计芯片
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildStatChip('已修', '${category.totalCourses}门', null),
                      _buildStatChip(
                        '已过',
                        '${category.passedCourses}门',
                        Theme.of(context).brightness == Brightness.dark
                            ? Colors.green.shade300
                            : Colors.green,
                      ),
                      if (category.failedCourses > 0)
                        _buildStatChip(
                          '未过',
                          '${category.failedCourses}门',
                          Theme.of(context).brightness == Brightness.dark
                              ? Colors.red.shade300
                              : Colors.red,
                        ),
                      if (category.missingRequiredCourses > 0)
                        _buildStatChip(
                          '缺修',
                          '${category.missingRequiredCourses}门',
                          Theme.of(context).brightness == Brightness.dark
                              ? Colors.orange.shade300
                              : Colors.orange,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // 展开的详细内容
          if (isExpanded && category.hasChildren) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 子分类
                  ...category.subcategories.map(
                    (subCategory) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildCategoryCard(
                        subCategory,
                        indent: indent + 1,
                      ),
                    ),
                  ),

                  // 课程列表
                  ...category.courses.map(
                    (course) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildCourseItem(course),
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

  /// 构建统计芯片
  ///
  /// 创建圆角容器，半透明背景，显示标签和数值
  /// 支持自定义颜色
  /// 满足需求: 7.3
  Widget _buildStatChip(String label, String value, Color? color) {
    final chipColor = color ?? Theme.of(context).colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? (color?.withValues(alpha: 0.25) ??
                  Colors.grey.withValues(alpha: 0.2))
            : (color?.withValues(alpha: 0.15) ??
                  Colors.grey.withValues(alpha: 0.1)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: chipColor),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: chipColor,
            ),
          ),
        ],
      ),
    );
  }

  /// 获取进度条颜色
  ///
  /// 根据完成百分比返回对应的颜色
  /// >= 100%: 绿色, >= 80%: 蓝色, < 80%: 橙色
  /// 适配深色模式
  /// 满足需求: 16.3, 16.4, 12.3
  Color _getProgressColor(double percentage) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (percentage >= 100) {
      return isDark ? Colors.green.shade300 : Colors.green;
    } else if (percentage >= 80) {
      return isDark ? Colors.blue.shade300 : Colors.blue;
    } else {
      return isDark ? Colors.orange.shade300 : Colors.orange;
    }
  }

  /// 构建课程项
  ///
  /// 显示课程代码、名称、学分、成绩和状态
  /// 满足需求: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6
  Widget _buildCourseItem(PlanCourse course) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 1.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 状态图标
          Icon(
            course.statusIcon,
            size: 20,
            color: course.getStatusColor(context),
          ),
          const SizedBox(width: 12),

          // 课程信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 课程代码和名称
                Text(
                  '[${course.courseCode}] ${course.courseName}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                const SizedBox(height: 4),

                // 学分、成绩和状态
                Row(
                  children: [
                    if (course.credits != null) ...[
                      Text(
                        '学分: ${course.credits!.toStringAsFixed(1)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    if (course.score != null) ...[
                      Text(
                        '成绩: ${course.score}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Text(
                      course.statusDescription,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: course.getStatusColor(context),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
