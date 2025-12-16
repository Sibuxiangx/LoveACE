import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import '../../models/aac/aac_credit_info.dart';
import '../../providers/aac_provider.dart';
import '../../services/logger_service.dart';
import '../widgets/winui_card.dart';
import '../widgets/winui_loading.dart';
import '../widgets/winui_empty_state.dart';
import '../widgets/winui_dialogs.dart';
import '../widgets/winui_notification.dart';

/// WinUI 风格的爱安财页面
///
/// 使用 TreeView 展示学分层级结构（分类 → 子项）
/// 桌面端利用宽屏空间，左侧树形导航，右侧详情
/// 复用 AACProvider 进行数据管理
/// _Requirements: 11.1, 11.2, 11.3, 11.4_
class WinUIAACPage extends StatefulWidget {
  const WinUIAACPage({super.key});

  @override
  State<WinUIAACPage> createState() => _WinUIAACPageState();
}

class _WinUIAACPageState extends State<WinUIAACPage> {
  /// 当前选中的分类
  AACCreditCategory? _selectedCategory;

  /// 当前选中的条目
  AACCreditItem? _selectedItem;

  /// 搜索关键词
  String _searchQuery = '';

  /// 选中的子类别（typeName）筛选 - 支持多选
  Set<String> _selectedTypeNames = {};

  /// 日期区间筛选 - 开始日期
  DateTime? _startDate;

  /// 日期区间筛选 - 结束日期
  DateTime? _endDate;

  /// 搜索控制器
  final TextEditingController _searchController = TextEditingController();

  /// 是否显示筛选面板
  bool _showFilters = false;

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

  /// 获取所有唯一的子类别名称
  List<String> _getAllTypeNames(List<AACCreditCategory> categories) {
    final typeNames = <String>{};
    for (final category in categories) {
      for (final item in category.children) {
        if (item.typeName.isNotEmpty) {
          typeNames.add(item.typeName);
        }
      }
    }
    return typeNames.toList()..sort();
  }

  /// 解析日期字符串
  DateTime? _parseDate(String dateStr) {
    try {
      // 格式: "2024-01-15 10:30:00" 或 "2024/01/15"
      final cleanStr = dateStr.split(' ').first.replaceAll('/', '-');
      return DateTime.parse(cleanStr);
    } catch (e) {
      return null;
    }
  }

  /// 筛选条目
  List<AACCreditItem> _filterItems(List<AACCreditItem> items) {
    return items.where((item) {
      // 搜索筛选
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        if (!item.title.toLowerCase().contains(query) &&
            !item.typeName.toLowerCase().contains(query)) {
          return false;
        }
      }

      // 子类别筛选（多选）
      if (_selectedTypeNames.isNotEmpty && !_selectedTypeNames.contains(item.typeName)) {
        return false;
      }

      // 日期筛选
      if (_startDate != null || _endDate != null) {
        final itemDate = _parseDate(item.addTime);
        if (itemDate == null) return false;

        if (_startDate != null && itemDate.isBefore(_startDate!)) {
          return false;
        }
        if (_endDate != null && itemDate.isAfter(_endDate!.add(const Duration(days: 1)))) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  /// 清除所有筛选条件
  void _clearFilters() {
    setState(() {
      _searchQuery = '';
      _searchController.clear();
      _selectedTypeNames = {};
      _startDate = null;
      _endDate = null;
    });
  }

  /// 是否有活跃的筛选条件（不含搜索）
  bool get _hasActiveFilters =>
      _selectedTypeNames.isNotEmpty ||
      _startDate != null ||
      _endDate != null;

  /// 是否有任何筛选（含搜索）
  bool get _hasAnyFilters =>
      _searchQuery.isNotEmpty || _hasActiveFilters;

  Future<void> _loadData({bool forceRefresh = false}) async {
    final provider = Provider.of<AACProvider?>(context, listen: false);
    if (provider == null) return;
    
    await provider.loadData(forceRefresh: forceRefresh);

    if (mounted && provider.state == AACState.error) {
      _showErrorDialog(provider.errorMessage ?? '加载失败', provider.isRetryable);
    }
  }

  Future<void> _refreshData() async {
    setState(() {
      _selectedCategory = null;
      _selectedItem = null;
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
    // 显示确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('导出爱安财分数'),
        content: const Text('确认导出爱安财详细分数为CSV文件？'),
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

    // 显示加载对话框
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
      final provider = Provider.of<AACProvider?>(context, listen: false);
      if (provider == null) return;
      
      await provider.exportToCSV();

      // 关闭加载对话框
      if (mounted) {
        Navigator.of(context).pop();

        // 显示成功通知
        WinUINotificationManager.showSuccess(
          context,
          title: '导出成功',
          content: 'CSV文件已导出',
        );
      }
    } catch (e) {
      LoggerService.error('❌ 导出CSV失败', error: e);

      // 关闭加载对话框
      if (mounted) {
        Navigator.of(context).pop();

        // 显示错误通知
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
    return Consumer<AACProvider?>(
      builder: (context, provider, child) {
        // Provider 为 null 时显示加载状态
        if (provider == null) {
          return const ScaffoldPage(
            header: PageHeader(title: Text('爱安财')),
            content: WinUILoading(message: '正在初始化...'),
          );
        }

        return ScaffoldPage(
          header: PageHeader(
            title: const Text('爱安财'),
            commandBar: CommandBar(
              mainAxisAlignment: MainAxisAlignment.end,
              primaryItems: [
                // 常驻搜索框
                CommandBarBuilderItem(
                  builder: (context, mode, child) => SizedBox(
                    width: 200,
                    child: TextBox(
                      controller: _searchController,
                      placeholder: '搜索标题或类别',
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
                CommandBarButton(
                  icon: Icon(
                    FluentIcons.filter,
                    color: _hasActiveFilters ? FluentTheme.of(context).accentColor : null,
                  ),
                  label: Text(_hasActiveFilters ? '筛选 (${_selectedTypeNames.length + (_startDate != null ? 1 : 0) + (_endDate != null ? 1 : 0)})' : '筛选'),
                  onPressed: provider.state == AACState.loaded
                      ? () => setState(() => _showFilters = !_showFilters)
                      : null,
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
                  onPressed: provider.state == AACState.loaded ? _exportCSV : null,
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

  /// 构建页面内容
  Widget _buildContent(BuildContext context, AACProvider provider) {
    // 加载中状态
    if (provider.state == AACState.loading) {
      return const WinUILoading(message: '正在加载爱安财数据');
    }

    // 加载完成状态
    if (provider.state == AACState.loaded &&
        provider.creditInfo != null &&
        provider.creditList != null) {
      return _buildMainLayout(context, provider);
    }

    // 错误状态
    if (provider.state == AACState.error) {
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

  /// 构建主布局（左侧树形导航 + 右侧详情）
  Widget _buildMainLayout(BuildContext context, AACProvider provider) {
    return Column(
      children: [
        // 筛选面板
        if (_showFilters) _buildFilterPanel(context, provider),
        // 主内容区
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左侧：总分卡片 + 树形导航
              SizedBox(
                width: 320,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildCreditInfoCard(context, provider),
                      const SizedBox(height: 16),
                      _buildCategoryList(context, provider),
                    ],
                  ),
                ),
              ),
              // 分隔线
              Container(
                width: 1,
                color: FluentTheme.of(context).resources.controlStrokeColorDefault,
              ),
              // 右侧：详情面板
              Expanded(
                child: _buildDetailPanel(context, provider),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 构建筛选面板
  Widget _buildFilterPanel(BuildContext context, AACProvider provider) {
    final theme = FluentTheme.of(context);
    final categories = provider.creditList!;
    final allTypeNames = _getAllTypeNames(categories);

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 第一行：日期筛选 + 统计 + 关闭按钮
          Row(
            children: [
              // 日期筛选标签
              Icon(FluentIcons.calendar, size: 14, color: theme.inactiveColor),
              const SizedBox(width: 8),
              Text('日期范围:', style: theme.typography.body),
              const SizedBox(width: 12),
              // 开始日期
              SizedBox(
                width: 130,
                child: DatePicker(
                  selected: _startDate,
                  onChanged: (date) {
                    setState(() {
                      _startDate = date;
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              Text('至', style: theme.typography.body),
              const SizedBox(width: 8),
              // 结束日期
              SizedBox(
                width: 130,
                child: DatePicker(
                  selected: _endDate,
                  onChanged: (date) {
                    setState(() {
                      _endDate = date;
                    });
                  },
                ),
              ),
              if (_startDate != null || _endDate != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(FluentIcons.clear, size: 12),
                  onPressed: () {
                    setState(() {
                      _startDate = null;
                      _endDate = null;
                    });
                  },
                ),
              ],
              const Spacer(),
              // 筛选结果统计
              if (_hasAnyFilters) _buildFilterStats(context, provider),
              const SizedBox(width: 12),
              // 关闭筛选面板
              IconButton(
                icon: const Icon(FluentIcons.chrome_close, size: 14),
                onPressed: () => setState(() => _showFilters = false),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 第二行：子类别多选
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(FluentIcons.tag, size: 14, color: theme.inactiveColor),
              const SizedBox(width: 8),
              Text('子类别:', style: theme.typography.body),
              const SizedBox(width: 12),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    // 全选/取消全选按钮
                    Button(
                      onPressed: () {
                        setState(() {
                          if (_selectedTypeNames.length == allTypeNames.length) {
                            _selectedTypeNames = {};
                          } else {
                            _selectedTypeNames = allTypeNames.toSet();
                          }
                        });
                      },
                      child: Text(
                        _selectedTypeNames.length == allTypeNames.length ? '取消全选' : '全选',
                      ),
                    ),
                    // 子类别标签
                    ...allTypeNames.map((name) {
                      final isSelected = _selectedTypeNames.contains(name);
                      return ToggleButton(
                        checked: isSelected,
                        onChanged: (checked) {
                          setState(() {
                            if (checked) {
                              _selectedTypeNames.add(name);
                            } else {
                              _selectedTypeNames.remove(name);
                            }
                          });
                        },
                        child: Text(
                          name,
                          style: TextStyle(
                            fontSize: 12,
                            color: isSelected ? theme.accentColor : null,
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建筛选结果统计
  Widget _buildFilterStats(BuildContext context, AACProvider provider) {
    final theme = FluentTheme.of(context);
    final categories = provider.creditList!;

    int totalItems = 0;
    int filteredItems = 0;
    double filteredScore = 0;

    for (final category in categories) {
      totalItems += category.children.length;
      final filtered = _filterItems(category.children);
      filteredItems += filtered.length;
      filteredScore += filtered.fold(0.0, (sum, item) => sum + item.score);
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
            '筛选结果: $filteredItems/$totalItems 项, ${filteredScore.toStringAsFixed(1)} 分',
            style: theme.typography.caption?.copyWith(
              color: theme.accentColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }


  /// 构建总分信息卡片
  Widget _buildCreditInfoCard(BuildContext context, AACProvider provider) {
    final theme = FluentTheme.of(context);
    final info = provider.creditInfo!;
    final categories = provider.creditList!;

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

    return WinUICard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    FluentIcons.heart,
                    size: 20,
                    color: theme.accentColor,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '爱安财总分',
                    style: theme.typography.subtitle,
                  ),
                ],
              ),
              // 达标状态标签
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: info.isTypeAdopt
                      ? Colors.green.withValues(alpha: 0.2)
                      : Colors.orange.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      info.isTypeAdopt
                          ? FluentIcons.check_mark
                          : FluentIcons.warning,
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
          const SizedBox(height: 16),
          // 总分显示
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                info.totalScore.toStringAsFixed(1),
                style: theme.typography.display?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.accentColor,
                ),
              ),
              if (practiceScore > 0) ...[
                Text(
                  ' + ${practiceScore.toStringAsFixed(1)}',
                  style: theme.typography.title?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: theme.accentColor.withValues(alpha: 0.7),
                  ),
                ),
              ],
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '分',
                  style: theme.typography.body?.copyWith(
                    color: theme.inactiveColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 分类数量
          Text(
            '共 ${categories.length} 个分类',
            style: theme.typography.caption?.copyWith(
              color: theme.inactiveColor,
            ),
          ),
          // 社会实践提示
          if (practiceScore > 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    FluentIcons.people,
                    size: 12,
                    color: theme.accentColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '含社会实践 +${practiceScore.toStringAsFixed(1)}',
                    style: theme.typography.caption?.copyWith(
                      color: theme.accentColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
          // 未达标原因
          if (!info.isTypeAdopt && info.typeAdoptResult.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(
                    FluentIcons.info,
                    size: 12,
                    color: Colors.orange,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      info.typeAdoptResult,
                      style: theme.typography.caption?.copyWith(
                        color: Colors.orange,
                      ),
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

  /// 构建分类列表
  Widget _buildCategoryList(BuildContext context, AACProvider provider) {
    final theme = FluentTheme.of(context);
    final categories = provider.creditList!;

    return WinUICard(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Icon(
                  FluentIcons.bulleted_list,
                  size: 16,
                  color: theme.accentColor,
                ),
                const SizedBox(width: 8),
                Text(
                  '分类列表',
                  style: theme.typography.bodyStrong,
                ),
              ],
            ),
          ),
          const Divider(),
          ...categories.map((category) => _buildCategoryItem(context, category)),
        ],
      ),
    );
  }

  /// 构建分类项
  Widget _buildCategoryItem(BuildContext context, AACCreditCategory category) {
    final theme = FluentTheme.of(context);
    final isSelected = _selectedCategory?.id == category.id;
    final filteredItems = _filterItems(category.children);
    final filteredScore = filteredItems.fold(0.0, (sum, item) => sum + item.score);
    final hasFilteredResults = filteredItems.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: HoverButton(
        onPressed: () {
          setState(() {
            _selectedCategory = category;
            _selectedItem = null;
          });
        },
        builder: (context, states) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: isSelected
                  ? theme.accentColor.withValues(alpha: 0.15)
                  : (states.isHovered
                      ? theme.resources.subtleFillColorSecondary
                      : null),
              border: isSelected
                  ? Border.all(color: theme.accentColor, width: 1.5)
                  : null,
            ),
            child: Opacity(
              opacity: _hasAnyFilters && !hasFilteredResults ? 0.5 : 1.0,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      category.typeName,
                      style: theme.typography.body?.copyWith(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 条目数量
                  Text(
                    _hasAnyFilters
                        ? '${filteredItems.length}/${category.children.length}项'
                        : '${category.children.length}项',
                    style: theme.typography.caption?.copyWith(
                      color: theme.inactiveColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 分数
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: theme.accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _hasAnyFilters
                          ? filteredScore.toStringAsFixed(1)
                          : category.totalScore.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: theme.accentColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    FluentIcons.chevron_right,
                    size: 12,
                    color: isSelected ? theme.accentColor : theme.inactiveColor,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }


  /// 构建详情面板
  Widget _buildDetailPanel(BuildContext context, AACProvider provider) {
    final theme = FluentTheme.of(context);

    // 如果没有选中任何内容，显示提示
    if (_selectedCategory == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.touch_pointer,
              size: 64,
              color: theme.inactiveColor,
            ),
            const SizedBox(height: 16),
            Text(
              '选择左侧分类查看详情',
              style: theme.typography.subtitle?.copyWith(
                color: theme.inactiveColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '点击分类或展开查看具体条目',
              style: theme.typography.body?.copyWith(
                color: theme.inactiveColor.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      );
    }

    // 如果选中了具体条目，显示条目详情
    if (_selectedItem != null) {
      return _buildItemDetail(context, _selectedItem!);
    }

    // 显示分类详情
    return _buildCategoryDetail(context, _selectedCategory!);
  }

  /// 构建分类详情
  Widget _buildCategoryDetail(BuildContext context, AACCreditCategory category) {
    final theme = FluentTheme.of(context);
    final isSocialPractice = category.typeName.contains('社会实践');
    final filteredItems = _filterItems(category.children);
    final filteredScore = filteredItems.fold(0.0, (sum, item) => sum + item.score);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 分类标题
          Row(
            children: [
              if (isSocialPractice) ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    FluentIcons.people,
                    size: 24,
                    color: theme.accentColor,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.typeName,
                      style: theme.typography.title,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _hasAnyFilters
                          ? '${filteredItems.length}/${category.children.length} 项记录 (已筛选)'
                          : '${category.children.length} 项记录',
                      style: theme.typography.body?.copyWith(
                        color: theme.inactiveColor,
                      ),
                    ),
                  ],
                ),
              ),
              // 总分
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      _hasAnyFilters ? '筛选分数' : '总分',
                      style: theme.typography.caption?.copyWith(
                        color: theme.inactiveColor,
                      ),
                    ),
                    Text(
                      _hasAnyFilters
                          ? filteredScore.toStringAsFixed(1)
                          : category.totalScore.toStringAsFixed(1),
                      style: theme.typography.title?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.accentColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // 条目列表
          Row(
            children: [
              Text(
                '分数明细',
                style: theme.typography.subtitle,
              ),
              if (_hasAnyFilters) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${filteredItems.length}',
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
          if (filteredItems.isEmpty)
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
                      '没有符合筛选条件的记录',
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
            ...filteredItems.map((item) => _buildItemCard(context, item)),
        ],
      ),
    );
  }

  /// 构建条目卡片
  Widget _buildItemCard(BuildContext context, AACCreditItem item) {
    final theme = FluentTheme.of(context);
    final isPractice = item.typeName.contains('三下乡') ||
        item.title.contains('三下乡') ||
        item.title.contains('社会实践');
    final isSelected = _selectedItem?.id == item.id;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Button(
        onPressed: () {
          setState(() {
            _selectedItem = item;
          });
        },
        style: ButtonStyle(
          padding: WidgetStateProperty.all(EdgeInsets.zero),
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? theme.accentColor
                  : (isPractice
                      ? theme.accentColor.withValues(alpha: 0.5)
                      : theme.resources.controlStrokeColorDefault),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              if (isPractice) ...[
                Icon(
                  FluentIcons.people,
                  size: 16,
                  color: theme.accentColor,
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: theme.typography.body?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (item.typeName.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.typeName,
                        style: theme.typography.caption?.copyWith(
                          color: theme.inactiveColor,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getScoreColor(item.score).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '+${item.score.toStringAsFixed(1)}',
                  style: TextStyle(
                    color: _getScoreColor(item.score),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建条目详情
  Widget _buildItemDetail(BuildContext context, AACCreditItem item) {
    final theme = FluentTheme.of(context);
    final isPractice = item.typeName.contains('三下乡') ||
        item.title.contains('三下乡') ||
        item.title.contains('社会实践');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 返回按钮
          Button(
            onPressed: () {
              setState(() {
                _selectedItem = null;
              });
            },
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
          // 条目详情卡片
          WinUICard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题行
                Row(
                  children: [
                    if (isPractice) ...[
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: theme.accentColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          FluentIcons.people,
                          size: 24,
                          color: theme.accentColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Text(
                        item.title,
                        style: theme.typography.title,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // 分数
                _buildDetailRow(context, '获得分数', '+${item.score.toStringAsFixed(1)} 分',
                    valueColor: _getScoreColor(item.score)),
                const SizedBox(height: 12),
                // 类别
                if (item.typeName.isNotEmpty) ...[
                  _buildDetailRow(context, '所属类别', item.typeName),
                  const SizedBox(height: 12),
                ],
                // 添加时间
                if (item.addTime.isNotEmpty) ...[
                  _buildDetailRow(context, '添加时间', item.addTime),
                  const SizedBox(height: 12),
                ],
                // 学号
                if (item.userNo.isNotEmpty) ...[
                  _buildDetailRow(context, '学号', item.userNo),
                ],
              ],
            ),
          ),
          // 社会实践提示
          if (isPractice) ...[
            const SizedBox(height: 16),
            InfoBar(
              title: const Text('社会实践分数'),
              content: const Text('此分数来自社会实践活动，将计入爱安财总分'),
              severity: InfoBarSeverity.info,
            ),
          ],
        ],
      ),
    );
  }

  /// 构建详情行
  Widget _buildDetailRow(BuildContext context, String label, String value, {Color? valueColor}) {
    final theme = FluentTheme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: theme.typography.body?.copyWith(
              color: theme.inactiveColor,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            value,
            style: theme.typography.body?.copyWith(
              fontWeight: FontWeight.w500,
              color: valueColor,
            ),
          ),
        ),
      ],
    );
  }

  /// 根据分数获取颜色
  Color _getScoreColor(double score) {
    if (score >= 10) {
      return Colors.red;
    } else if (score >= 5) {
      return Colors.orange;
    } else if (score >= 2) {
      return Colors.blue;
    } else {
      return Colors.green;
    }
  }
}
