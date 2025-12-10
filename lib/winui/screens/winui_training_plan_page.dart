import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/jwc/plan_category.dart';
import '../../models/jwc/plan_completion_info.dart';
import '../../models/jwc/plan_course.dart';
import '../../providers/training_plan_provider.dart';
import '../../services/logger_service.dart';
import '../widgets/winui_card.dart';
import '../widgets/winui_loading.dart';
import '../widgets/winui_empty_state.dart';
import '../widgets/winui_dialogs.dart';
import '../widgets/winui_notification.dart';

/// 排序选项
enum _SortOption {
  defaultOrder,
  unreadFirst,
  passedFirst,
  creditDesc,
  creditAsc,
  nameAsc,
}

extension _SortOptionExtension on _SortOption {
  String get label {
    switch (this) {
      case _SortOption.defaultOrder:
        return '默认排序';
      case _SortOption.unreadFirst:
        return '未修读优先';
      case _SortOption.passedFirst:
        return '已通过优先';
      case _SortOption.creditDesc:
        return '学分从高到低';
      case _SortOption.creditAsc:
        return '学分从低到高';
      case _SortOption.nameAsc:
        return '按名称排序';
    }
  }
}

/// WinUI 风格的培养方案页面
///
/// 使用 TreeView 展示培养方案层级结构（分类 → 课程）
/// 桌面端充分利用空间，支持多级展开
/// 复用 TrainingPlanProvider 进行数据管理
/// _Requirements: 9.1, 9.2, 9.3, 9.4_
class WinUITrainingPlanPage extends StatefulWidget {
  const WinUITrainingPlanPage({super.key});

  @override
  State<WinUITrainingPlanPage> createState() => _WinUITrainingPlanPageState();
}

class _WinUITrainingPlanPageState extends State<WinUITrainingPlanPage> {
  /// 当前选中的分类
  PlanCategory? _selectedCategory;

  /// 当前选中的课程
  PlanCourse? _selectedCourse;

  /// TreeView 的项目列表（缓存以保持展开状态）
  List<TreeViewItem>? _treeItems;

  /// 上次构建树的数据版本
  PlanCompletionInfo? _lastPlanInfo;

  /// 搜索关键词
  String _searchQuery = '';

  /// 搜索控制器
  final TextEditingController _searchController = TextEditingController();

  /// 是否显示筛选面板
  bool _showFilters = false;

  /// 修读状态筛选
  Set<String> _selectedStatuses = {}; // '已通过', '未通过', '未修读'

  /// 排序方式
  _SortOption _sortOption = _SortOption.defaultOrder;

  /// 可用的修读状态
  static const List<String> _allStatuses = ['已通过', '未通过', '未修读'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 筛选课程
  List<PlanCourse> _filterCourses(List<PlanCourse> courses) {
    var filtered = courses.where((course) {
      // 搜索筛选
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        if (!course.courseName.toLowerCase().contains(query) &&
            !course.courseCode.toLowerCase().contains(query)) {
          return false;
        }
      }

      // 修读状态筛选
      if (_selectedStatuses.isNotEmpty &&
          !_selectedStatuses.contains(course.statusDescription)) {
        return false;
      }

      return true;
    }).toList();

    // 排序
    switch (_sortOption) {
      case _SortOption.defaultOrder:
        break;
      case _SortOption.unreadFirst:
        filtered.sort((a, b) {
          final aOrder = a.statusDescription == '未修读' ? 0 : (a.statusDescription == '未通过' ? 1 : 2);
          final bOrder = b.statusDescription == '未修读' ? 0 : (b.statusDescription == '未通过' ? 1 : 2);
          return aOrder.compareTo(bOrder);
        });
      case _SortOption.passedFirst:
        filtered.sort((a, b) {
          final aOrder = a.isPassed ? 0 : (a.statusDescription == '未通过' ? 1 : 2);
          final bOrder = b.isPassed ? 0 : (b.statusDescription == '未通过' ? 1 : 2);
          return aOrder.compareTo(bOrder);
        });
      case _SortOption.creditDesc:
        filtered.sort((a, b) => (b.credits ?? 0).compareTo(a.credits ?? 0));
      case _SortOption.creditAsc:
        filtered.sort((a, b) => (a.credits ?? 0).compareTo(b.credits ?? 0));
      case _SortOption.nameAsc:
        filtered.sort((a, b) => a.courseName.compareTo(b.courseName));
    }

    return filtered;
  }

  /// 清除所有筛选条件
  void _clearFilters() {
    setState(() {
      _searchQuery = '';
      _searchController.clear();
      _selectedStatuses = {};
      _sortOption = _SortOption.defaultOrder;
    });
  }

  /// 是否有活跃的筛选条件
  bool get _hasActiveFilters => _selectedStatuses.isNotEmpty;

  /// 是否有任何筛选（含搜索和排序）
  bool get _hasAnyFilters =>
      _searchQuery.isNotEmpty ||
      _selectedStatuses.isNotEmpty ||
      _sortOption != _SortOption.defaultOrder;

  /// 复制课程号到剪贴板
  Future<void> _copyCourseCode(BuildContext context, String courseCode) async {
    await Clipboard.setData(ClipboardData(text: courseCode));
    if (context.mounted) {
      WinUINotificationManager.showSuccess(
        context,
        title: '已复制',
        content: '课程号 $courseCode 已复制到剪贴板',
      );
    }
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    final provider = Provider.of<TrainingPlanProvider>(context, listen: false);
    await provider.loadData(forceRefresh: forceRefresh);

    if (mounted && provider.state == TrainingPlanState.error) {
      _showErrorDialog(provider.errorMessage ?? '加载失败', provider.isRetryable);
    }
  }

  Future<void> _refreshData() async {
    setState(() {
      _selectedCategory = null;
      _selectedCourse = null;
      _treeItems = null; // 清除缓存的树，强制重建
      _lastPlanInfo = null;
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

  /// 导出 CSV
  Future<void> _exportCSV() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('导出培养方案'),
        content: const Text('确认导出培养方案完成情况为CSV文件？'),
        actions: [
          Button(
            child: const Text('取消'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          FilledButton(
            child: const Text('导出'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ContentDialog(
        title: const Text('正在导出'),
        content: const Row(
          children: [
            ProgressRing(),
            SizedBox(width: 16),
            Text('正在导出CSV文件...'),
          ],
        ),
        actions: const [],
      ),
    );

    try {
      final provider = Provider.of<TrainingPlanProvider>(context, listen: false);
      await provider.exportToCSV();

      if (mounted) {
        Navigator.of(context).pop();
        WinUINotificationManager.showSuccess(
          context,
          title: '导出成功',
          content: 'CSV文件已导出',
        );
      }
    } catch (e) {
      LoggerService.error('❌ 导出CSV失败', error: e);
      if (mounted) {
        Navigator.of(context).pop();
        WinUINotificationManager.showError(
          context,
          title: '导出失败',
          content: e.toString(),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TrainingPlanProvider>(
      builder: (context, provider, child) {
        return ScaffoldPage(
          header: PageHeader(
            title: const Text('培养方案'),
            commandBar: CommandBar(
              mainAxisAlignment: MainAxisAlignment.end,
              primaryItems: [
                // 常驻搜索框
                CommandBarBuilderItem(
                  builder: (context, mode, child) => SizedBox(
                    width: 200,
                    child: TextBox(
                      controller: _searchController,
                      placeholder: '搜索课程名或课程号',
                      prefix: const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(FluentIcons.search, size: 14),
                      ),
                      suffix: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(FluentIcons.clear, size: 12),
                              onPressed: () {
                                setState(() {
                                  _searchQuery = '';
                                  _searchController.clear();
                                });
                              },
                            )
                          : null,
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                        });
                      },
                    ),
                  ),
                  wrappedItem: CommandBarButton(
                    icon: const Icon(FluentIcons.search),
                    label: const Text('搜索'),
                    onPressed: () {},
                  ),
                ),
                const CommandBarSeparator(),
                // 筛选按钮
                CommandBarButton(
                  icon: Icon(
                    FluentIcons.filter,
                    color: _hasActiveFilters
                        ? FluentTheme.of(context).accentColor
                        : null,
                  ),
                  label: Text(_hasActiveFilters
                      ? '筛选 (${_selectedStatuses.length})'
                      : '筛选'),
                  onPressed: provider.state == TrainingPlanState.loaded
                      ? () => setState(() => _showFilters = !_showFilters)
                      : null,
                ),
                // 排序下拉
                CommandBarBuilderItem(
                  builder: (context, mode, child) => ComboBox<_SortOption>(
                    value: _sortOption,
                    items: _SortOption.values
                        .map((opt) => ComboBoxItem<_SortOption>(
                              value: opt,
                              child: Text(opt.label),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _sortOption = value;
                        });
                      }
                    },
                  ),
                  wrappedItem: CommandBarButton(
                    icon: const Icon(FluentIcons.sort),
                    label: const Text('排序'),
                    onPressed: () {},
                  ),
                ),
                // 清除筛选按钮 - 始终存在，但根据状态禁用
                CommandBarButton(
                  icon: const Icon(FluentIcons.clear_filter),
                  label: const Text('清除'),
                  onPressed: _hasAnyFilters ? _clearFilters : null,
                ),
                const CommandBarSeparator(),
                CommandBarButton(
                  icon: const Icon(FluentIcons.download),
                  label: const Text('导出CSV'),
                  onPressed:
                      provider.state == TrainingPlanState.loaded ? _exportCSV : null,
                ),
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

  Widget _buildContent(BuildContext context, TrainingPlanProvider provider) {
    if (provider.state == TrainingPlanState.loading) {
      return const WinUILoading(message: '正在加载培养方案');
    }

    if (provider.state == TrainingPlanState.loaded && provider.planInfo != null) {
      return _buildMainLayout(context, provider);
    }

    if (provider.state == TrainingPlanState.error) {
      return WinUIEmptyState.needRefresh(
        title: '数据加载失败',
        description: provider.errorMessage ?? '请点击刷新重新加载',
        onAction: _refreshData,
      );
    }

    return WinUIEmptyState.noData(
      title: '暂无数据',
      description: '点击右上角刷新按钮加载数据',
      actionText: '刷新',
      onAction: _refreshData,
    );
  }

  Widget _buildMainLayout(BuildContext context, TrainingPlanProvider provider) {
    final planInfo = provider.planInfo!;

    return Column(
      children: [
        // 筛选面板
        if (_showFilters) _buildFilterPanel(context),
        // 主内容区
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左侧：总览卡片 + 树形导航
              SizedBox(
                width: 360,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildSummaryCard(context, planInfo),
                      const SizedBox(height: 16),
                      _buildCategoryTree(context, planInfo),
                    ],
                  ),
                ),
              ),
              Container(
                width: 1,
                color: FluentTheme.of(context).resources.controlStrokeColorDefault,
              ),
              // 右侧：详情面板
              Expanded(
                child: _buildDetailPanel(context, planInfo),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 构建筛选面板
  Widget _buildFilterPanel(BuildContext context) {
    final theme = FluentTheme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.resources.cardBackgroundFillColorDefault,
        border: Border(
          bottom: BorderSide(
            color: theme.resources.controlStrokeColorDefault,
          ),
        ),
      ),
      child: Row(
        children: [
          // 修读状态筛选
          Icon(FluentIcons.filter, size: 14, color: theme.inactiveColor),
          const SizedBox(width: 8),
          Text('修读状态:', style: theme.typography.body),
          const SizedBox(width: 12),
          // 状态标签
          ...List.generate(_allStatuses.length, (index) {
            final status = _allStatuses[index];
            final isSelected = _selectedStatuses.contains(status);
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ToggleButton(
                checked: isSelected,
                onChanged: (checked) {
                  setState(() {
                    if (checked) {
                      _selectedStatuses.add(status);
                    } else {
                      _selectedStatuses.remove(status);
                    }
                  });
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getStatusIcon(status),
                      size: 12,
                      color: isSelected ? _getStatusColor(status, theme) : null,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      status,
                      style: TextStyle(
                        fontSize: 12,
                        color: isSelected ? _getStatusColor(status, theme) : null,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          const Spacer(),
          // 筛选结果统计
          if (_hasAnyFilters) _buildFilterStats(context),
          const SizedBox(width: 12),
          // 关闭筛选面板
          IconButton(
            icon: const Icon(FluentIcons.chrome_close, size: 14),
            onPressed: () => setState(() => _showFilters = false),
          ),
        ],
      ),
    );
  }

  /// 获取状态图标
  IconData _getStatusIcon(String status) {
    switch (status) {
      case '已通过':
        return FluentIcons.check_mark;
      case '未通过':
        return FluentIcons.cancel;
      case '未修读':
        return FluentIcons.clock;
      default:
        return FluentIcons.info;
    }
  }

  /// 获取状态颜色
  Color _getStatusColor(String status, FluentThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    switch (status) {
      case '已通过':
        return isDark ? Colors.green.light : Colors.green;
      case '未通过':
        return isDark ? Colors.red.light : Colors.red;
      case '未修读':
        return isDark ? Colors.orange.light : Colors.orange;
      default:
        return theme.accentColor;
    }
  }

  /// 构建筛选结果统计
  Widget _buildFilterStats(BuildContext context) {
    final theme = FluentTheme.of(context);
    final provider = Provider.of<TrainingPlanProvider>(context, listen: false);
    final planInfo = provider.planInfo;
    if (planInfo == null) return const SizedBox.shrink();

    int totalCourses = 0;
    int filteredCourses = 0;

    void countCourses(PlanCategory category) {
      totalCourses += category.courses.length;
      filteredCourses += _filterCourses(category.courses).length;
      for (final sub in category.subcategories) {
        countCourses(sub);
      }
    }

    for (final category in planInfo.categories) {
      countCourses(category);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.accentColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(FluentIcons.filter, size: 12, color: theme.accentColor),
          const SizedBox(width: 6),
          Text(
            '筛选结果: $filteredCourses/$totalCourses 门课程',
            style: theme.typography.caption?.copyWith(
              color: theme.accentColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }


  /// 构建总览卡片
  Widget _buildSummaryCard(BuildContext context, PlanCompletionInfo info) {
    final theme = FluentTheme.of(context);

    return WinUICard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(FluentIcons.education, size: 20, color: theme.accentColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  info.planName,
                  style: theme.typography.subtitle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 专业和年级
          Row(
            children: [
              _buildInfoChip(context, '专业', info.major),
              const SizedBox(width: 8),
              _buildInfoChip(context, '年级', info.grade),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),
          // 预估毕业学分
          Center(
            child: Column(
              children: [
                Text(
                  '预估毕业学分',
                  style: theme.typography.caption?.copyWith(
                    color: theme.inactiveColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${info.estimatedGraduationCredits.toStringAsFixed(1)}',
                  style: theme.typography.display?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.accentColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),
          // 课程统计
          Builder(builder: (context) {
            final isDark = FluentTheme.of(context).brightness == Brightness.dark;
            return Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _buildStatItem(context, '总分类', '${info.totalCategories}', FluentIcons.folder, theme.accentColor)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildStatItem(context, '总课程', '${info.totalCourses}', FluentIcons.education, isDark ? Colors.blue.light : Colors.blue)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _buildStatItem(context, '已过', '${info.passedCourses}', FluentIcons.check_mark, isDark ? Colors.green.light : Colors.green)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildStatItem(context, '未过', '${info.failedCourses}', FluentIcons.cancel, info.failedCourses > 0 ? (isDark ? Colors.red.light : Colors.red) : (isDark ? Colors.grey[100] : Colors.grey))),
                    const SizedBox(width: 8),
                    Expanded(child: _buildStatItem(context, '未修', '${info.unreadCourses}', FluentIcons.clock, isDark ? Colors.orange.light : Colors.orange)),
                  ],
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildInfoChip(BuildContext context, String label, String value) {
    final theme = FluentTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.accentColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$label: $value',
        style: theme.typography.caption?.copyWith(
          color: theme.accentColor,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildStatItem(BuildContext context, String label, String value, IconData icon, Color color) {
    final theme = FluentTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 4),
          Text(value, style: theme.typography.bodyStrong?.copyWith(color: color)),
          Text(label, style: theme.typography.caption?.copyWith(color: theme.inactiveColor)),
        ],
      ),
    );
  }

  /// 构建或获取缓存的 TreeView 项目列表
  List<TreeViewItem> _getOrBuildTreeItems(PlanCompletionInfo info) {
    // 如果数据没变且已有缓存，直接返回
    if (_treeItems != null && _lastPlanInfo == info) {
      return _treeItems!;
    }
    // 构建新的树并缓存
    _lastPlanInfo = info;
    _treeItems = info.categories.map((cat) => _buildCategoryTreeItem(cat)).toList();
    return _treeItems!;
  }

  /// 构建分类树形导航（只显示分类，不显示课程叶节点）
  Widget _buildCategoryTree(BuildContext context, PlanCompletionInfo info) {
    final theme = FluentTheme.of(context);
    final treeItems = _getOrBuildTreeItems(info);

    return WinUICard(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Icon(FluentIcons.bulleted_tree_list, size: 16, color: theme.accentColor),
                const SizedBox(width: 8),
                Text('分类列表', style: theme.typography.bodyStrong),
              ],
            ),
          ),
          const Divider(),
          TreeView(
            shrinkWrap: true,
            selectionMode: TreeViewSelectionMode.single,
            items: treeItems,
            onItemInvoked: (item, reason) async {
              if (item.value is PlanCategory) {
                setState(() {
                  _selectedCategory = item.value as PlanCategory;
                  _selectedCourse = null;
                });
              }
            },
            onSelectionChanged: (selectedItems) async {
              if (selectedItems.isEmpty) return;
              final item = selectedItems.first;
              if (item.value is PlanCategory) {
                setState(() {
                  _selectedCategory = item.value as PlanCategory;
                  _selectedCourse = null;
                });
              }
            },
          ),
        ],
      ),
    );
  }

  /// 构建分类树节点（递归，只包含子分类，不包含课程）
  TreeViewItem _buildCategoryTreeItem(PlanCategory category) {
    final hasSubcategories = category.subcategories.isNotEmpty;
    
    // 递归构建子分类
    final childItems = hasSubcategories
        ? category.subcategories.map((sub) => _buildCategoryTreeItem(sub)).toList()
        : <TreeViewItem>[];

    return TreeViewItem(
      value: category,
      lazy: false,
      content: _TreeItemContent(
        category: category,
        getProgressColor: _getProgressColor,
      ),
      children: childItems,
    );
  }

  /// 构建详情面板
  Widget _buildDetailPanel(BuildContext context, PlanCompletionInfo info) {
    final theme = FluentTheme.of(context);

    if (_selectedCategory == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(FluentIcons.touch_pointer, size: 64, color: theme.inactiveColor),
            const SizedBox(height: 16),
            Text('选择左侧分类查看详情', style: theme.typography.subtitle?.copyWith(color: theme.inactiveColor)),
            const SizedBox(height: 8),
            Text('点击分类或展开查看具体课程', style: theme.typography.body?.copyWith(color: theme.inactiveColor.withValues(alpha: 0.7))),
          ],
        ),
      );
    }

    if (_selectedCourse != null) {
      return _buildCourseDetail(context, _selectedCourse!);
    }

    return _buildCategoryDetail(context, _selectedCategory!);
  }

  Widget _buildCategoryDetail(BuildContext context, PlanCategory category) {
    final theme = FluentTheme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 分类标题
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(category.categoryName, style: theme.typography.title),
                    const SizedBox(height: 4),
                    Text(
                      '${category.courses.length} 门课程 · ${category.subcategories.length} 个子分类',
                      style: theme.typography.body?.copyWith(color: theme.inactiveColor),
                    ),
                  ],
                ),
              ),
              if (category.isCompleted)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(FluentIcons.check_mark, size: 14, color: Colors.green),
                      const SizedBox(width: 4),
                      Text('已达标', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          // 学分进度
          WinUICard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('学分进度', style: theme.typography.bodyStrong),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ProgressBar(value: (category.completionPercentage / 100).clamp(0.0, 1.0) * 100),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${category.completionPercentage.toStringAsFixed(1)}%',
                      style: theme.typography.bodyStrong?.copyWith(color: _getProgressColor(category.completionPercentage)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('最低学分: ${category.minCredits.toStringAsFixed(1)}', style: theme.typography.caption),
                    Text('已获学分: ${category.completedCredits.toStringAsFixed(1)}', style: theme.typography.caption?.copyWith(color: _getProgressColor(category.completionPercentage))),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 课程统计
          WinUICard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('课程统计', style: theme.typography.bodyStrong),
                const SizedBox(height: 12),
                Builder(builder: (context) {
                  final isDark = FluentTheme.of(context).brightness == Brightness.dark;
                  return Row(
                    children: [
                      Expanded(child: _buildDetailStatItem(context, '已修', '${category.totalCourses}', isDark ? Colors.blue.light : Colors.blue)),
                      const SizedBox(width: 8),
                      Expanded(child: _buildDetailStatItem(context, '已过', '${category.passedCourses}', isDark ? Colors.green.light : Colors.green)),
                      const SizedBox(width: 8),
                      Expanded(child: _buildDetailStatItem(context, '未过', '${category.failedCourses}', category.failedCourses > 0 ? (isDark ? Colors.red.light : Colors.red) : (isDark ? Colors.grey[100] : Colors.grey))),
                      const SizedBox(width: 8),
                      Expanded(child: _buildDetailStatItem(context, '缺修', '${category.missingRequiredCourses}', category.missingRequiredCourses > 0 ? (isDark ? Colors.orange.light : Colors.orange) : (isDark ? Colors.grey[100] : Colors.grey))),
                    ],
                  );
                }),
              ],
            ),
          ),
          // 课程列表
          if (category.courses.isNotEmpty) ...[
            const SizedBox(height: 16),
            Builder(builder: (context) {
              final filteredCourses = _filterCourses(category.courses);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('课程列表', style: theme.typography.subtitle),
                      if (_hasAnyFilters) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.accentColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${filteredCourses.length}/${category.courses.length}',
                            style: theme.typography.caption?.copyWith(
                              color: theme.accentColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (filteredCourses.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            Icon(
                              FluentIcons.filter,
                              size: 48,
                              color: theme.inactiveColor,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '没有符合筛选条件的课程',
                              style: theme.typography.body?.copyWith(
                                color: theme.inactiveColor,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Button(
                              onPressed: _clearFilters,
                              child: const Text('清除筛选'),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ...filteredCourses
                        .map((course) => _buildCourseCard(context, course)),
                ],
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailStatItem(BuildContext context, String label, String value, Color color) {
    final theme = FluentTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(value, style: theme.typography.title?.copyWith(fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(label, style: theme.typography.caption?.copyWith(color: theme.inactiveColor)),
        ],
      ),
    );
  }

  Widget _buildCourseCard(BuildContext context, PlanCourse course) {
    final theme = FluentTheme.of(context);
    final isSelected = _selectedCourse?.courseCode == course.courseCode;
    final isDark = theme.brightness == Brightness.dark;

    // 根据课程状态获取颜色和图标
    final (IconData icon, Color color) = _getCourseStatusStyle(course, isDark);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: HoverButton(
        onPressed: () => setState(() => _selectedCourse = course),
        builder: (context, states) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: states.isHovered
                  ? theme.resources.subtleFillColorSecondary
                  : null,
              border: Border.all(
                color: isSelected
                    ? theme.accentColor
                    : theme.resources.controlStrokeColorDefault,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        course.courseName.isNotEmpty
                            ? course.courseName
                            : course.courseCode,
                        style: theme.typography.body
                            ?.copyWith(fontWeight: FontWeight.w500),
                      ),
                      if (course.courseCode.isNotEmpty)
                        Row(
                          children: [
                            Text(
                              course.courseCode,
                              style: theme.typography.caption
                                  ?.copyWith(color: theme.inactiveColor),
                            ),
                            const SizedBox(width: 4),
                            // 复制课程号按钮
                            Tooltip(
                              message: '复制课程号',
                              child: IconButton(
                                icon: Icon(
                                  FluentIcons.copy,
                                  size: 12,
                                  color: states.isHovered
                                      ? theme.accentColor
                                      : theme.inactiveColor,
                                ),
                                onPressed: () =>
                                    _copyCourseCode(context, course.courseCode),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                if (course.credits != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${course.credits}学分',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.accentColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
  
  /// 获取课程状态的图标和颜色
  (IconData, Color) _getCourseStatusStyle(PlanCourse course, bool isDark) {
    if (course.isPassed) {
      return (FluentIcons.check_mark, isDark ? Colors.green.light : Colors.green);
    } else if (course.statusDescription == '未通过') {
      return (FluentIcons.cancel, isDark ? Colors.red.light : Colors.red);
    } else {
      // 未修
      return (FluentIcons.clock, isDark ? Colors.orange.light : Colors.orange);
    }
  }

  Widget _buildCourseDetail(BuildContext context, PlanCourse course) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final (icon, color) = _getCourseStatusStyle(course, isDark);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Button(
            onPressed: () => setState(() => _selectedCourse = null),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(FluentIcons.back, size: 14),
                SizedBox(width: 8),
                Text('返回分类'),
              ],
            ),
          ),
          const SizedBox(height: 24),
          WinUICard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 24, color: color),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(course.courseName.isNotEmpty ? course.courseName : course.courseCode, style: theme.typography.title),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 80,
                      child: Text(
                        '课程代码',
                        style: theme.typography.body
                            ?.copyWith(color: theme.inactiveColor),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Row(
                        children: [
                          Text(
                            course.courseCode,
                            style: theme.typography.body
                                ?.copyWith(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(width: 8),
                          Button(
                            onPressed: () =>
                                _copyCourseCode(context, course.courseCode),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(FluentIcons.copy, size: 12),
                                SizedBox(width: 4),
                                Text('复制'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (course.credits != null) ...[
                  _buildDetailRow(context, '学分', '${course.credits}'),
                  const SizedBox(height: 12),
                ],
                if (course.courseType.isNotEmpty) ...[
                  _buildDetailRow(context, '课程类型', course.courseType),
                  const SizedBox(height: 12),
                ],
                _buildDetailRow(context, '状态', course.statusDescription, valueColor: color),
                if (course.score != null) ...[
                  const SizedBox(height: 12),
                  _buildDetailRow(context, '成绩', course.score!),
                ],
                if (course.examDate != null) ...[
                  const SizedBox(height: 12),
                  _buildDetailRow(context, '考试日期', course.examDate!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, String label, String value, {Color? valueColor}) {
    final theme = FluentTheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(label, style: theme.typography.body?.copyWith(color: theme.inactiveColor)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(value, style: theme.typography.body?.copyWith(fontWeight: FontWeight.w500, color: valueColor)),
        ),
      ],
    );
  }

  Color _getProgressColor(double percentage) {
    if (percentage >= 100) return Colors.green;
    if (percentage >= 60) return Colors.blue;
    if (percentage >= 30) return Colors.orange;
    return Colors.red;
  }
}

/// TreeView 项目内容组件
class _TreeItemContent extends StatelessWidget {
  final PlanCategory category;
  final Color Function(double) getProgressColor;

  const _TreeItemContent({
    required this.category,
    required this.getProgressColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    
    return Row(
      children: [
        // 完成状态图标
        if (category.isCompleted)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Icon(FluentIcons.check_mark, size: 12, color: Colors.green),
          ),
        // 分类名称
        Expanded(
          child: Text(
            category.categoryName,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 6),
        // 课程数量
        Text(
          '${category.courses.length}门',
          style: TextStyle(
            fontSize: 10,
            color: theme.inactiveColor,
          ),
        ),
        const SizedBox(width: 6),
        // 完成进度
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: getProgressColor(category.completionPercentage).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${category.completionPercentage.toStringAsFixed(0)}%',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: getProgressColor(category.completionPercentage),
            ),
          ),
        ),
      ],
    );
  }
}
