import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' show Material;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/jwc/course_schedule_record.dart';
import '../../models/jwc/plan_category.dart';
import '../../models/jwc/plan_completion_info.dart';
import '../../models/jwc/plan_course.dart';
import '../../providers/course_schedule_provider.dart';
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

/// 搜索建议类型
enum _SuggestionType {
  category,
  course,
}

/// 搜索建议项
class _SearchSuggestion {
  final _SuggestionType type;
  final PlanCategory? category;
  final PlanCourse? course;
  final String displayName;

  _SearchSuggestion({
    required this.type,
    this.category,
    this.course,
    required this.displayName,
  });
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

  /// 是否显示开课查询面板
  bool _showCourseSchedulePanel = true;

  /// 开课查询教师筛选控制器
  final TextEditingController _scheduleTeacherController = TextEditingController();

  /// 搜索建议的FocusNode
  final FocusNode _searchFocusNode = FocusNode();

  /// 搜索建议的OverlayEntry
  OverlayEntry? _searchOverlayEntry;

  /// 搜索框的GlobalKey
  final GlobalKey _searchBoxKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // 监听搜索框焦点变化
    _searchFocusNode.addListener(() {
      if (!_searchFocusNode.hasFocus) {
        // 延迟关闭，以便点击建议项时能够触发
        Future.delayed(const Duration(milliseconds: 200), () {
          if (!_searchFocusNode.hasFocus) {
            _removeSearchOverlay();
          }
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scheduleTeacherController.dispose();
    _searchFocusNode.dispose();
    _removeSearchOverlay();
    super.dispose();
  }

  /// 移除搜索建议overlay
  void _removeSearchOverlay() {
    _searchOverlayEntry?.remove();
    _searchOverlayEntry = null;
  }

  /// 选择课程（统一处理，包括重置开课查询状态）
  void _selectCourse(PlanCourse? course, {PlanCategory? category}) {
    // 如果切换到不同的课程，重置开课查询状态（但保持面板展开）
    if (_selectedCourse?.courseCode != course?.courseCode) {
      Provider.of<CourseScheduleProvider>(context, listen: false).reset();
    }
    _selectedCourse = course;
    if (category != null) {
      _selectedCategory = category;
    }
  }

  /// 显示搜索建议overlay
  void _showSearchOverlay(BuildContext context) {
    _removeSearchOverlay();
    
    final renderBox = _searchBoxKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    _searchOverlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: offset.dx,
        top: offset.dy + size.height + 4,
        width: 300,
        child: _buildSearchSuggestions(context),
      ),
    );

    Overlay.of(context).insert(_searchOverlayEntry!);
  }

  /// 获取搜索建议（分类和课程）
  List<_SearchSuggestion> _getSearchSuggestions(PlanCompletionInfo? planInfo) {
    if (planInfo == null || _searchQuery.isEmpty) return [];

    final suggestions = <_SearchSuggestion>[];
    final query = _searchQuery.toLowerCase();

    // 递归搜索分类和课程
    void searchCategory(PlanCategory category) {
      // 搜索分类名称
      if (category.categoryName.toLowerCase().contains(query)) {
        suggestions.add(_SearchSuggestion(
          type: _SuggestionType.category,
          category: category,
          displayName: category.categoryName,
        ));
      }

      // 搜索课程
      for (final course in category.courses) {
        if (course.courseName.toLowerCase().contains(query) ||
            course.courseCode.toLowerCase().contains(query)) {
          suggestions.add(_SearchSuggestion(
            type: _SuggestionType.course,
            course: course,
            category: category,
            displayName: course.courseName.isNotEmpty ? course.courseName : course.courseCode,
          ));
        }
      }

      // 递归搜索子分类
      for (final sub in category.subcategories) {
        searchCategory(sub);
      }
    }

    for (final category in planInfo.categories) {
      searchCategory(category);
    }

    return suggestions;
  }

  /// 构建搜索建议下拉框
  Widget _buildSearchSuggestions(BuildContext context) {
    final theme = FluentTheme.of(context);
    final provider = Provider.of<TrainingPlanProvider?>(context, listen: false);
    if (provider == null) return const SizedBox.shrink();
    
    final suggestions = _getSearchSuggestions(provider.planInfo);

    if (suggestions.isEmpty) {
      return Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.menuColor,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: theme.resources.controlStrokeColorDefault),
          ),
          child: Text(
            '未找到匹配结果',
            style: theme.typography.body?.copyWith(color: theme.inactiveColor),
          ),
        ),
      );
    }

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 300),
        decoration: BoxDecoration(
          color: theme.menuColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: theme.resources.controlStrokeColorDefault),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 可滚动的建议列表（不限制数量）
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: suggestions
                      .map((suggestion) =>
                          _buildSuggestionItem(context, suggestion))
                      .toList(),
                ),
              ),
            ),
            // 底部显示总数
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: theme.resources.controlStrokeColorDefault),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(FluentIcons.search, size: 12, color: theme.inactiveColor),
                  const SizedBox(width: 6),
                  Text(
                    '共 ${suggestions.length} 个结果',
                    style: theme.typography.caption?.copyWith(color: theme.inactiveColor),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建单个搜索建议项
  Widget _buildSuggestionItem(BuildContext context, _SearchSuggestion suggestion) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final isCategory = suggestion.type == _SuggestionType.category;
    final icon = isCategory ? FluentIcons.folder : FluentIcons.education;
    final iconColor = isCategory
        ? (isDark ? Colors.orange.light : Colors.orange)
        : (isDark ? Colors.blue.light : Colors.blue);

    return HoverButton(
      onPressed: () {
        _removeSearchOverlay();
        setState(() {
          // 展开到目标节点的路径（在setState内部调用以触发UI更新）
          _expandPathToNode(suggestion.category, suggestion.course);
          if (isCategory) {
            _selectedCategory = suggestion.category;
            _selectCourse(null);
          } else {
            _selectCourse(suggestion.course, category: suggestion.category);
          }
          // 清空搜索
          _searchQuery = '';
          _searchController.clear();
        });
      },
      builder: (context, states) => Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: states.isHovered ? theme.resources.subtleFillColorSecondary : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    suggestion.displayName,
                    style: theme.typography.body,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (!isCategory && suggestion.course != null)
                    Text(
                      suggestion.course!.courseCode,
                      style: theme.typography.caption?.copyWith(color: theme.inactiveColor),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                isCategory ? '分类' : '课程',
                style: TextStyle(fontSize: 10, color: iconColor),
              ),
            ),
          ],
        ),
      ),
    );
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
      _rebuildTree(); // 重建树以清除筛选
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
    final provider = Provider.of<TrainingPlanProvider?>(context, listen: false);
    if (provider == null) return;
    
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
      final provider = Provider.of<TrainingPlanProvider?>(context, listen: false);
      if (provider == null) return;
      
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
    return Consumer<TrainingPlanProvider?>(
      builder: (context, provider, child) {
        // Provider 为 null 时显示加载状态
        if (provider == null) {
          return const ScaffoldPage(
            header: PageHeader(title: Text('培养方案')),
            content: WinUILoading(message: '正在初始化...'),
          );
        }

        return ScaffoldPage(
          header: PageHeader(
            title: const Text('培养方案'),
            commandBar: CommandBar(
              mainAxisAlignment: MainAxisAlignment.end,
              primaryItems: [
                // 常驻搜索框（带搜索建议）
                CommandBarBuilderItem(
                  builder: (context, mode, child) => SizedBox(
                    key: _searchBoxKey,
                    width: 200,
                    child: TextBox(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
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
                                _removeSearchOverlay();
                              },
                            )
                          : null,
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                        });
                        // 显示搜索建议
                        if (value.isNotEmpty && provider.state == TrainingPlanState.loaded) {
                          _showSearchOverlay(context);
                        } else {
                          _removeSearchOverlay();
                        }
                      },
                      onTap: () {
                        // 点击时如果有内容也显示建议
                        if (_searchQuery.isNotEmpty && provider.state == TrainingPlanState.loaded) {
                          _showSearchOverlay(context);
                        }
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
                          _rebuildTree(); // 重建树以应用排序
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
                    _rebuildTree(); // 重建树以应用筛选
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
    final provider = Provider.of<TrainingPlanProvider?>(context, listen: false);
    if (provider == null) return const SizedBox.shrink();
    
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

  /// 需要展开的分类ID集合
  final Set<String> _expandedCategoryIds = {};

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

  /// 强制重建树
  void _rebuildTree() {
    _treeItems = null;
    _lastPlanInfo = null;
  }

  /// 展开到指定节点的最短路径
  void _expandPathToNode(PlanCategory? targetCategory, PlanCourse? targetCourse) {
    final provider = Provider.of<TrainingPlanProvider?>(context, listen: false);
    if (provider == null) return;
    
    final planInfo = provider.planInfo;
    if (planInfo == null) {
      LoggerService.warning('⚠️ planInfo is null, cannot expand path');
      return;
    }

    LoggerService.info('🔍 展开路径: category=${targetCategory?.categoryName}, course=${targetCourse?.courseName}');

    // 在原始数据结构中查找路径
    bool findPath(List<PlanCategory> categories, List<String> path) {
      for (final category in categories) {
        // 检查是否是目标分类（仅当没有指定课程时）
        if (targetCategory != null && 
            targetCourse == null && 
            category.categoryId == targetCategory.categoryId) {
          path.add(category.categoryId);
          LoggerService.info('✅ 找到目标分类: ${category.categoryName}');
          return true;
        }
        
        // 如果目标是课程，检查当前分类是否包含该课程
        if (targetCourse != null) {
          for (final course in category.courses) {
            if (course.courseCode == targetCourse.courseCode) {
              path.add(category.categoryId);
              LoggerService.info('✅ 找到包含目标课程的分类: ${category.categoryName}');
              return true;
            }
          }
        }
        
        // 递归搜索子分类
        if (category.subcategories.isNotEmpty) {
          path.add(category.categoryId);
          if (findPath(category.subcategories, path)) {
            LoggerService.info('📂 路径包含: ${category.categoryName}');
            return true;
          }
          path.removeLast();
        }
      }
      return false;
    }

    // 查找路径
    final path = <String>[];
    final found = findPath(planInfo.categories, path);
    
    if (found) {
      // 将路径上的所有分类ID添加到展开集合
      _expandedCategoryIds.addAll(path);
      LoggerService.info('🔍 展开路径: $path');
      // 强制重建树
      _rebuildTree();
    } else {
      LoggerService.warning('⚠️ 未找到目标节点');
    }
  }

  /// 构建分类树形导航（显示分类和课程叶节点）
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
              // 双击时切换展开/折叠状态
              if (item.children.isNotEmpty) {
                setState(() {
                  item.expanded = !item.expanded;
                });
              }
              // 同时更新选中状态
              if (item.value is PlanCategory) {
                setState(() {
                  _selectedCategory = item.value as PlanCategory;
                  _selectCourse(null);
                });
              } else if (item.value is PlanCourse) {
                // 点击课程节点，找到其所属分类
                final course = item.value as PlanCourse;
                final category = _findCategoryForCourse(info, course);
                setState(() {
                  _selectCourse(course, category: category);
                });
              }
            },
            onSelectionChanged: (selectedItems) async {
              if (selectedItems.isEmpty) return;
              final item = selectedItems.first;
              if (item.value is PlanCategory) {
                setState(() {
                  _selectedCategory = item.value as PlanCategory;
                  _selectCourse(null);
                });
              } else if (item.value is PlanCourse) {
                final course = item.value as PlanCourse;
                final category = _findCategoryForCourse(info, course);
                setState(() {
                  _selectCourse(course, category: category);
                });
              }
            },
          ),
        ],
      ),
    );
  }

  /// 查找课程所属的分类
  PlanCategory? _findCategoryForCourse(PlanCompletionInfo info, PlanCourse course) {
    PlanCategory? findInCategory(PlanCategory category) {
      // 检查当前分类的课程
      for (final c in category.courses) {
        if (c.courseCode == course.courseCode) {
          return category;
        }
      }
      // 递归检查子分类
      for (final sub in category.subcategories) {
        final found = findInCategory(sub);
        if (found != null) return found;
      }
      return null;
    }

    for (final category in info.categories) {
      final found = findInCategory(category);
      if (found != null) return found;
    }
    return null;
  }

  /// 构建分类树节点（递归，包含子分类和课程叶节点，应用筛选和排序）
  TreeViewItem _buildCategoryTreeItem(PlanCategory category) {
    final childItems = <TreeViewItem>[];
    
    // 先添加子分类（递归构建，可能因筛选而为空）
    for (final sub in category.subcategories) {
      final subItem = _buildCategoryTreeItem(sub);
      // 如果子分类有内容（子分类或课程），才添加
      if (subItem.children.isNotEmpty || _hasFilteredCourses(sub)) {
        childItems.add(subItem);
      }
    }
    
    // 再添加课程叶节点（应用筛选和排序）
    final filteredCourses = _filterCourses(category.courses);
    for (final course in filteredCourses) {
      childItems.add(_buildCourseTreeItem(course));
    }

    // 检查是否需要展开（在 _expandedCategoryIds 中）
    final shouldExpand = _expandedCategoryIds.contains(category.categoryId);

    return TreeViewItem(
      value: category,
      lazy: false,
      expanded: shouldExpand, // 根据 _expandedCategoryIds 决定是否展开
      content: _TreeItemContent(
        category: category,
        getProgressColor: _getProgressColor,
        filteredCount: filteredCourses.length,
        totalCount: category.courses.length,
      ),
      children: childItems,
    );
  }

  /// 检查分类是否有符合筛选条件的课程（递归检查子分类）
  bool _hasFilteredCourses(PlanCategory category) {
    // 检查当前分类的课程
    if (_filterCourses(category.courses).isNotEmpty) {
      return true;
    }
    // 递归检查子分类
    for (final sub in category.subcategories) {
      if (_hasFilteredCourses(sub)) {
        return true;
      }
    }
    return false;
  }

  /// 构建课程树节点（叶节点）
  TreeViewItem _buildCourseTreeItem(PlanCourse course) {
    return TreeViewItem(
      value: course,
      lazy: false,
      content: _CourseTreeItemContent(course: course),
      children: const [],
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
        onPressed: () => setState(() => _selectCourse(course)),
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
          const SizedBox(height: 16),
          // 开课查询面板
          _buildCourseSchedulePanel(context, course),
        ],
      ),
    );
  }

  /// 构建开课查询面板
  Widget _buildCourseSchedulePanel(BuildContext context, PlanCourse course) {
    final theme = FluentTheme.of(context);
    final scheduleProvider = Provider.of<CourseScheduleProvider>(context);

    // 默认展开时自动加载学期列表
    if (_showCourseSchedulePanel && scheduleProvider.termState == ScheduleTermState.initial) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        scheduleProvider.loadTermList();
      });
    }

    return WinUICard(
      padding: const EdgeInsets.all(0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏
          HoverButton(
            onPressed: () {
              setState(() => _showCourseSchedulePanel = !_showCourseSchedulePanel);
              // 展开时加载学期列表
              if (_showCourseSchedulePanel && scheduleProvider.termState == ScheduleTermState.initial) {
                scheduleProvider.loadTermList();
              }
            },
            builder: (context, states) => Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    _showCourseSchedulePanel ? FluentIcons.chevron_down : FluentIcons.chevron_right,
                    size: 12,
                    color: theme.accentColor,
                  ),
                  const SizedBox(width: 8),
                  Icon(FluentIcons.calendar, size: 16, color: theme.accentColor),
                  const SizedBox(width: 8),
                  Text('开课查询', style: theme.typography.bodyStrong),
                  const Spacer(),
                  if (scheduleProvider.state == CourseScheduleState.loaded)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.accentColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${scheduleProvider.filteredCount}/${scheduleProvider.totalCount}',
                        style: theme.typography.caption?.copyWith(
                          color: theme.accentColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // 展开内容
          if (_showCourseSchedulePanel) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 学期选择和查询按钮
                  _buildScheduleQueryBar(context, course, scheduleProvider),
                  const SizedBox(height: 16),
                  // 筛选条件
                  if (scheduleProvider.state == CourseScheduleState.loaded)
                    _buildScheduleFilters(context, scheduleProvider),
                  // 查询结果
                  _buildScheduleResults(context, scheduleProvider),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 构建查询栏
  Widget _buildScheduleQueryBar(
    BuildContext context,
    PlanCourse course,
    CourseScheduleProvider scheduleProvider,
  ) {
    // 获取学期列表
    final termList = scheduleProvider.termList ?? [];
    final selectedTermCode = scheduleProvider.selectedTermCode ??
        (termList.isNotEmpty ? termList.first.termCode : null);

    return Row(
      children: [
        // 学期选择
        Expanded(
          child: scheduleProvider.termState == ScheduleTermState.loading
              ? const Row(
                  children: [
                    ProgressRing(strokeWidth: 2),
                    SizedBox(width: 8),
                    Text('加载学期...'),
                  ],
                )
              : scheduleProvider.termState == ScheduleTermState.error
                  ? Row(
                      children: [
                        Icon(FluentIcons.error_badge, size: 14, color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            scheduleProvider.termErrorMessage ?? '加载失败',
                            style: TextStyle(color: Colors.red, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Button(
                          onPressed: () => scheduleProvider.loadTermList(),
                          child: const Text('重试'),
                        ),
                      ],
                    )
                  : ComboBox<String>(
                      value: selectedTermCode,
                      placeholder: const Text('选择学期'),
                      items: termList
                          .map((term) => ComboBoxItem<String>(
                                value: term.termCode,
                                child: Text(term.termName),
                              ))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          scheduleProvider.setSelectedTermCode(value);
                        }
                      },
                    ),
        ),
        const SizedBox(width: 12),
        // 查询按钮
        FilledButton(
          onPressed: scheduleProvider.state == CourseScheduleState.loading ||
                  selectedTermCode == null ||
                  course.courseCode.isEmpty
              ? null
              : () {
                  scheduleProvider.queryCourseSchedule(
                    courseCode: course.courseCode,
                    termCode: selectedTermCode,
                  );
                },
          child: scheduleProvider.state == CourseScheduleState.loading
              ? const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: ProgressRing(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('查询中'),
                  ],
                )
              : const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.search, size: 14),
                    SizedBox(width: 8),
                    Text('查询开课'),
                  ],
                ),
        ),
      ],
    );
  }

  /// 构建筛选条件
  Widget _buildScheduleFilters(BuildContext context, CourseScheduleProvider provider) {
    final theme = FluentTheme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: theme.resources.cardBackgroundFillColorSecondary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.resources.controlStrokeColorDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(FluentIcons.filter, size: 14, color: theme.inactiveColor),
              const SizedBox(width: 8),
              Text('筛选条件', style: theme.typography.caption?.copyWith(color: theme.inactiveColor)),
              const Spacer(),
              if (provider.hasActiveFilters)
                Button(
                  onPressed: () {
                    provider.clearFilters();
                    _scheduleTeacherController.clear();
                  },
                  child: const Text('清除筛选'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              // 校区筛选
              SizedBox(
                width: 140,
                child: ComboBox<String?>(
                  value: provider.filterCampus,
                  placeholder: const Text('全部校区'),
                  items: [
                    const ComboBoxItem<String?>(value: null, child: Text('全部校区')),
                    ...provider.availableCampuses.map((campus) => ComboBoxItem<String?>(
                          value: campus,
                          child: Text(campus),
                        )),
                  ],
                  onChanged: (value) => provider.setFilterCampus(value),
                ),
              ),
              // 星期筛选
              SizedBox(
                width: 120,
                child: ComboBox<int?>(
                  value: provider.filterWeekday,
                  placeholder: const Text('全部星期'),
                  items: [
                    const ComboBoxItem<int?>(value: null, child: Text('全部星期')),
                    ...List.generate(7, (i) => ComboBoxItem<int?>(
                          value: i + 1,
                          child: Text(['周一', '周二', '周三', '周四', '周五', '周六', '周日'][i]),
                        )),
                  ],
                  onChanged: (value) => provider.setFilterWeekday(value),
                ),
              ),
              // 教师搜索
              SizedBox(
                width: 160,
                child: TextBox(
                  controller: _scheduleTeacherController,
                  placeholder: '搜索教师',
                  prefix: const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(FluentIcons.search, size: 12),
                  ),
                  onChanged: (value) => provider.setFilterTeacher(value),
                ),
              ),
              // 只显示有余量
              ToggleButton(
                checked: provider.filterHasCapacity,
                onChanged: (checked) => provider.setFilterHasCapacity(checked),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.check_mark, size: 12),
                    SizedBox(width: 4),
                    Text('有余量'),
                  ],
                ),
              ),
              // 排序
              SizedBox(
                width: 140,
                child: ComboBox<CourseScheduleSortOption>(
                  value: provider.sortOption,
                  items: CourseScheduleSortOption.values
                      .map((opt) => ComboBoxItem<CourseScheduleSortOption>(
                            value: opt,
                            child: Text(opt.label),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) provider.setSortOption(value);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建查询结果
  Widget _buildScheduleResults(BuildContext context, CourseScheduleProvider provider) {
    final theme = FluentTheme.of(context);

    switch (provider.state) {
      case CourseScheduleState.initial:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                Icon(FluentIcons.calendar, size: 48, color: theme.inactiveColor),
                const SizedBox(height: 12),
                Text(
                  '选择学期后点击查询',
                  style: theme.typography.body?.copyWith(color: theme.inactiveColor),
                ),
              ],
            ),
          ),
        );

      case CourseScheduleState.loading:
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              children: [
                ProgressRing(),
                SizedBox(height: 12),
                Text('正在查询开课情况...'),
              ],
            ),
          ),
        );

      case CourseScheduleState.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                Icon(FluentIcons.error_badge, size: 48, color: Colors.red),
                const SizedBox(height: 12),
                Text(
                  provider.errorMessage ?? '查询失败',
                  style: theme.typography.body?.copyWith(color: Colors.red),
                ),
                const SizedBox(height: 12),
                if (provider.isRetryable)
                  Button(
                    onPressed: () {
                      if (provider.currentCourseCode != null &&
                          provider.currentTermCode != null) {
                        provider.queryCourseSchedule(
                          courseCode: provider.currentCourseCode!,
                          termCode: provider.currentTermCode!,
                        );
                      }
                    },
                    child: const Text('重试'),
                  ),
              ],
            ),
          ),
        );

      case CourseScheduleState.loaded:
        final records = provider.filteredRecords;
        if (records.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(FluentIcons.calendar, size: 48, color: theme.inactiveColor),
                  const SizedBox(height: 12),
                  Text(
                    provider.totalCount == 0 ? '该学期暂无开课' : '没有符合筛选条件的课程',
                    style: theme.typography.body?.copyWith(color: theme.inactiveColor),
                  ),
                  if (provider.hasActiveFilters) ...[
                    const SizedBox(height: 12),
                    Button(
                      onPressed: () {
                        provider.clearFilters();
                        _scheduleTeacherController.clear();
                      },
                      child: const Text('清除筛选'),
                    ),
                  ],
                ],
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '共 ${records.length} 个开课班级',
              style: theme.typography.caption?.copyWith(color: theme.inactiveColor),
            ),
            const SizedBox(height: 12),
            ...records.map((record) => _buildScheduleRecordCard(context, record)),
          ],
        );
    }
  }

  /// 构建单个开课记录卡片
  Widget _buildScheduleRecordCard(BuildContext context, CourseScheduleRecord record) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // 计算余量状态
    final hasCapacity = record.bkskyl != null && record.bkskyl! > 0;
    final capacityColor = hasCapacity
        ? (isDark ? Colors.green.light : Colors.green)
        : (isDark ? Colors.red.light : Colors.red);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.resources.controlStrokeColorDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行：课序号、教师、余量
          Row(
            children: [
              // 课序号
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${record.kxh ?? '-'}班',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: theme.accentColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 教师
              if (record.teacherName != null && record.teacherName!.isNotEmpty)
                Expanded(
                  child: Row(
                    children: [
                      Icon(FluentIcons.contact, size: 12, color: theme.inactiveColor),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          record.teacherName!,
                          style: theme.typography.body,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                )
              else
                const Spacer(),
              // 余量
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: capacityColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      hasCapacity ? FluentIcons.check_mark : FluentIcons.cancel,
                      size: 10,
                      color: capacityColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '余${record.bkskyl ?? 0}/${record.bkskrl ?? 0}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: capacityColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 第二行：时间地点
          Row(
            children: [
              Icon(FluentIcons.clock, size: 12, color: theme.inactiveColor),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  record.scheduleDescription,
                  style: theme.typography.caption,
                ),
              ),
            ],
          ),
          // 第三行：校区、选课限制
          if (record.xkxzsm != null && record.xkxzsm!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(FluentIcons.info, size: 12, color: theme.inactiveColor),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    record.xkxzsm!.replaceAll('\r\n', ' ').trim(),
                    style: theme.typography.caption?.copyWith(
                      color: theme.inactiveColor,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
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

/// TreeView 项目内容组件（分类）
class _TreeItemContent extends StatelessWidget {
  final PlanCategory category;
  final Color Function(double) getProgressColor;
  final int? filteredCount;
  final int? totalCount;

  const _TreeItemContent({
    required this.category,
    required this.getProgressColor,
    this.filteredCount,
    this.totalCount,
  });

  /// 递归计算分类及其所有子分类中的课程总数
  int _getTotalCourseCount(PlanCategory cat) {
    int count = cat.courses.length;
    for (final sub in cat.subcategories) {
      count += _getTotalCourseCount(sub);
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final totalCourses = _getTotalCourseCount(category);
    final hasFilter = filteredCount != null && totalCount != null && filteredCount != totalCount;
    
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
        // 课程数量（如果有筛选显示筛选后/总数，否则显示总数）
        Text(
          hasFilter ? '$filteredCount/$totalCount门' : '$totalCourses门',
          style: TextStyle(
            fontSize: 10,
            color: hasFilter ? theme.accentColor : theme.inactiveColor,
            fontWeight: hasFilter ? FontWeight.bold : FontWeight.normal,
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

/// TreeView 项目内容组件（课程叶节点）
class _CourseTreeItemContent extends StatelessWidget {
  final PlanCourse course;

  const _CourseTreeItemContent({
    required this.course,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // 获取状态颜色和图标
    final (IconData icon, Color color) = _getCourseStatusStyle(isDark);
    
    return Row(
      children: [
        // 状态图标
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 6),
        // 课程名称
        Expanded(
          child: Text(
            course.courseName.isNotEmpty ? course.courseName : course.courseCode,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12),
          ),
        ),
        // 学分
        if (course.credits != null) ...[
          const SizedBox(width: 6),
          Text(
            '${course.credits}分',
            style: TextStyle(
              fontSize: 10,
              color: theme.inactiveColor,
            ),
          ),
        ],
      ],
    );
  }

  /// 获取课程状态的图标和颜色
  (IconData, Color) _getCourseStatusStyle(bool isDark) {
    if (course.isPassed) {
      return (FluentIcons.check_mark, isDark ? Colors.green.light : Colors.green);
    } else if (course.statusDescription == '未通过') {
      return (FluentIcons.cancel, isDark ? Colors.red.light : Colors.red);
    } else {
      // 未修
      return (FluentIcons.clock, isDark ? Colors.orange.light : Colors.orange);
    }
  }
}
