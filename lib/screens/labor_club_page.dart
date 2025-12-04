import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/labor_club_provider.dart';
import '../providers/theme_provider.dart';
import '../models/labor_club/labor_club_activity.dart';
import '../models/labor_club/labor_club_info.dart';
import '../models/labor_club/activity_detail.dart';
import '../widgets/adaptive_sliver_app_bar.dart';
import '../widgets/glass_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_indicator.dart';
import '../widgets/retryable_error_dialog.dart';
import '../widgets/app_background.dart';
import '../utils/platform/platform_util.dart';
import 'scan_sign_in_page.dart';

/// 劳动俱乐部页面
///
/// 提供劳动修课进度查看、活动浏览和报名功能
/// 支持自动加载、手动刷新和下拉刷新
class LaborClubPage extends StatefulWidget {
  const LaborClubPage({super.key});

  @override
  State<LaborClubPage> createState() => _LaborClubPageState();
}

/// 视图模式枚举
enum ViewMode {
  /// 我的活动
  myActivities,

  /// 添加活动
  addActivities,

  /// 扫码签到
  scan,
}

class _LaborClubPageState extends State<LaborClubPage> {
  /// 当前视图模式
  ViewMode _currentView = ViewMode.myActivities;

  /// 展开状态管理（默认全部展开）
  final Map<String, bool> _expandedCategories = {
    'ongoing': true,
    'finished': true,
    'available': true,
    'full': true,
    'notStarted': true,
    'expired': true,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  /// 加载数据
  Future<void> _loadData({bool forceRefresh = false}) async {
    final provider = Provider.of<LaborClubProvider>(context, listen: false);
    await provider.loadData(forceRefresh: forceRefresh);

    if (mounted && provider.state == LaborClubState.error) {
      _showErrorDialog(provider.errorMessage ?? '加载失败', provider.isRetryable);
    }
  }

  /// 刷新数据
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

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final hasBackground = themeProvider.backgroundPath != null;

    return Scaffold(
      backgroundColor: hasBackground ? Colors.transparent : null,
      body: AppBackground(
        child: Consumer<LaborClubProvider>(
          builder: (context, provider, child) {
            // 加载中状态
            if (provider.state == LaborClubState.loading) {
              return CustomScrollView(
                slivers: [
                  _buildAppBar(),
                  const SliverLoadingIndicator(message: '正在加载数据...'),
                ],
              );
            }

            // 加载完成状态
            if (provider.state == LaborClubState.loaded) {
              return RefreshIndicator(
                onRefresh: _refreshData,
                child: CustomScrollView(
                  slivers: [
                    _buildAppBar(),
                    SliverPadding(
                      padding: const EdgeInsets.all(16),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          // 进度卡片
                          _buildProgressCard(provider),
                          const SizedBox(height: 16),
                          // 俱乐部信息卡片
                          if (provider.clubs != null &&
                              provider.clubs!.isNotEmpty)
                            ..._buildClubInfoCards(provider),
                          const SizedBox(height: 16),
                          // 根据视图模式显示不同内容
                          if (_currentView == ViewMode.myActivities)
                            _buildMyActivitiesView(provider)
                          else if (_currentView == ViewMode.addActivities)
                            _buildAddActivitiesView(provider),
                        ]),
                      ),
                    ),
                  ],
                ),
              );
            }

            // 错误状态
            if (provider.state == LaborClubState.error) {
              return CustomScrollView(
                slivers: [
                  _buildAppBar(),
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
                _buildAppBar(),
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

  /// 构建 AppBar
  Widget _buildAppBar() {
    // 检查是否支持扫码（非桌面平台）
    final supportsScan =
        !PlatformUtil.isWindows  &&
        !PlatformUtil.isLinux;

    return AdaptiveSliverAppBar(
      title: '劳动俱乐部',
      actions: [
        // 视图切换菜单
        PopupMenuButton<ViewMode>(
          icon: const Icon(Icons.view_list),
          tooltip: '切换视图',
          onSelected: (ViewMode mode) {
            setState(() {
              _currentView = mode;
            });
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: ViewMode.myActivities,
              child: Row(
                children: [
                  Icon(Icons.event_note),
                  SizedBox(width: 8),
                  Text('我的活动'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: ViewMode.addActivities,
              child: Row(
                children: [
                  Icon(Icons.add_circle_outline),
                  SizedBox(width: 8),
                  Text('添加活动'),
                ],
              ),
            ),
          ],
        ),
        // 扫码按钮（仅移动平台）
        if (supportsScan)
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: _navigateToScan,
            tooltip: '扫码签到',
          ),
        // 刷新按钮
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _refreshData,
          tooltip: '刷新',
        ),
      ],
    );
  }

  /// 导航到扫码页面
  void _navigateToScan() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const ScanSignInPage()));
  }

  /// 构建进度卡片
  Widget _buildProgressCard(LaborClubProvider provider) {
    final progressInfo = provider.progressInfo;
    if (progressInfo == null) return const SizedBox.shrink();

    final isCompleted = progressInfo.isCompleted;
    final percentage = progressInfo.progressPercentage;

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '劳动修课进度',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              // 达标状态标签
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? (isCompleted
                            ? Colors.green.withValues(alpha: 0.3)
                            : Colors.orange.withValues(alpha: 0.3))
                      : (isCompleted
                            ? Colors.green.withValues(alpha: 0.2)
                            : Colors.orange.withValues(alpha: 0.2)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isCompleted ? Icons.check_circle : Icons.cancel,
                      size: 14,
                      color: isCompleted ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isCompleted ? '已达标' : '未达标',
                      style: TextStyle(
                        color: isCompleted ? Colors.green : Colors.orange,
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
          // 完成次数
          Row(
            children: [
              Text(
                '${progressInfo.finishCount}',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).primaryColor,
                ),
              ),
              Text(
                ' / 10',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '次',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 进度条
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: percentage / 100,
              minHeight: 8,
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).primaryColor,
            ),
          ),
          const SizedBox(height: 8),
          // 进度百分比
          Text(
            '${percentage.toStringAsFixed(0)}%',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (!isCompleted) ...[
            const SizedBox(height: 8),
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
                    Icons.info_outline,
                    size: 12,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.blue.shade300
                        : Colors.blue,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '还需完成 ${10 - progressInfo.finishCount} 次活动',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.blue.shade300
                            : Colors.blue,
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

  /// 构建俱乐部信息卡片列表
  List<Widget> _buildClubInfoCards(LaborClubProvider provider) {
    final clubs = provider.clubs ?? [];
    return clubs
        .map(
          (club) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _buildClubInfoCard(club),
          ),
        )
        .toList();
  }

  /// 构建单个俱乐部信息卡片
  Widget _buildClubInfoCard(LaborClubInfo club) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 俱乐部图标
              if (club.ico?.isNotEmpty == true)
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.groups),
                )
              else
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.groups),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      club.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      club.typeName ?? '',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          _buildInfoRow(context, '会长', club.chairmanName ?? '未知'),
          const SizedBox(height: 8),
          _buildInfoRow(context, '成员数', '${club.memberNum} 人'),
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
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  /// 构建"我的活动"视图
  Widget _buildMyActivitiesView(LaborClubProvider provider) {
    final ongoingActivities = provider.ongoingActivities;
    final finishedActivities = provider.finishedActivities;

    if (ongoingActivities.isEmpty && finishedActivities.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: EmptyState.noData(title: '暂无活动', description: '您还没有报名任何活动'),
        ),
      );
    }

    return Column(
      children: [
        // 待开始的活动（已加入但未开始）
        _buildExpandableCard(
          'ongoing',
          '待开始',
          '${ongoingActivities.length} 个活动',
          Column(
            children: ongoingActivities.isEmpty
                ? [
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('暂无待开始的活动'),
                    ),
                  ]
                : ongoingActivities
                      .map(
                        (activity) => _buildActivityCard(
                          activity,
                          '待开始',
                          showSignInStatus: true,
                        ),
                      )
                      .toList(),
          ),
        ),
        const SizedBox(height: 16),
        // 已开始的活动（包括进行中和已结束）
        _buildExpandableCard(
          'finished',
          '已开始',
          '${finishedActivities.length} 个活动',
          Column(
            children: finishedActivities.isEmpty
                ? [
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('暂无已开始的活动'),
                    ),
                  ]
                : finishedActivities
                      .map(
                        (activity) => _buildActivityCard(
                          activity,
                          _getActivityStatusLabel(activity),
                          showSignInStatus: true,
                        ),
                      )
                      .toList(),
          ),
        ),
      ],
    );
  }

  /// 获取活动状态标签
  String _getActivityStatusLabel(LaborClubActivity activity) {
    try {
      final now = DateTime.now();
      final endTime = DateTime.parse(activity.endTime);
      if (endTime.isBefore(now)) {
        return '已结束';
      } else {
        return '进行中';
      }
    } catch (e) {
      return '已开始';
    }
  }

  /// 构建可展开卡片
  Widget _buildExpandableCard(
    String categoryId,
    String title,
    String subtitle,
    Widget content,
  ) {
    final isExpanded = _expandedCategories[categoryId] ?? false;

    return GlassCard(
      padding: const EdgeInsets.all(0),
      child: Column(
        children: [
          // 可点击的标题区域
          InkWell(
            onTap: () {
              setState(() {
                _expandedCategories[categoryId] = !isExpanded;
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).primaryColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
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
                ],
              ),
            ),
          ),
          // 展开的详细内容
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(padding: const EdgeInsets.all(16), child: content),
          ],
        ],
      ),
    );
  }

  /// 构建"添加活动"视图
  Widget _buildAddActivitiesView(LaborClubProvider provider) {
    final availableActivities = provider.availableActivities;
    final fullActivities = provider.fullActivities;
    final notStartedActivities = provider.notStartedActivities;
    final expiredActivities = provider.expiredActivities;

    if (availableActivities.isEmpty &&
        fullActivities.isEmpty &&
        notStartedActivities.isEmpty &&
        expiredActivities.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: EmptyState.noData(title: '暂无活动', description: '当前没有可报名的活动'),
        ),
      );
    }

    return Column(
      children: [
        // 可报名
        if (availableActivities.isNotEmpty) ...[
          _buildExpandableCard(
            'available',
            '可报名',
            '${availableActivities.length} 个活动',
            Column(
              children: availableActivities
                  .map(
                    (activity) => _buildActivityCard(
                      activity,
                      provider.isActivityJoined(activity.id) ? '已加入' : '可报名',
                      showApplyButton: !provider.isActivityJoined(activity.id),
                      showJoinedStatus: provider.isActivityJoined(activity.id),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 16),
        ],
        // 已满员
        if (fullActivities.isNotEmpty) ...[
          _buildExpandableCard(
            'full',
            '已满员',
            '${fullActivities.length} 个活动',
            Column(
              children: fullActivities
                  .map(
                    (activity) => _buildActivityCard(
                      activity,
                      provider.isActivityJoined(activity.id) ? '已加入' : '已满员',
                      showJoinedStatus: provider.isActivityJoined(activity.id),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 16),
        ],
        // 未开始报名
        if (notStartedActivities.isNotEmpty) ...[
          _buildExpandableCard(
            'notStarted',
            '未开始报名',
            '${notStartedActivities.length} 个活动',
            Column(
              children: notStartedActivities
                  .map(
                    (activity) => _buildActivityCard(
                      activity,
                      provider.isActivityJoined(activity.id) ? '已加入' : '未开始',
                      showJoinedStatus: provider.isActivityJoined(activity.id),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 16),
        ],
        // 已过期
        if (expiredActivities.isNotEmpty) ...[
          _buildExpandableCard(
            'expired',
            '已过期',
            '${expiredActivities.length} 个活动',
            Column(
              children: expiredActivities
                  .map(
                    (activity) => _buildActivityCard(
                      activity,
                      provider.isActivityJoined(activity.id) ? '已加入' : '已过期',
                      showJoinedStatus: provider.isActivityJoined(activity.id),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ],
    );
  }

  /// 构建活动卡片
  Widget _buildActivityCard(
    LaborClubActivity activity,
    String statusLabel, {
    bool showApplyButton = false,
    bool showSignInStatus = false,
    bool showJoinedStatus = false,
  }) {
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');

    // 解析时间
    DateTime? startTime;
    DateTime? endTime;
    try {
      startTime = DateTime.parse(activity.startTime);
      endTime = DateTime.parse(activity.endTime);
    } catch (e) {
      // 时间解析失败，使用原始字符串
    }

    // 状态颜色
    Color statusColor;
    switch (statusLabel) {
      case '进行中':
        statusColor = Colors.green;
        break;
      case '已结束':
        statusColor = Colors.grey;
        break;
      case '可报名':
        statusColor = Colors.blue;
        break;
      case '已满员':
        statusColor = Colors.orange;
        break;
      case '未开始':
        statusColor = Colors.purple;
        break;
      case '已过期':
        statusColor = Colors.red;
        break;
      case '待开始':
        statusColor = Colors.teal;
        break;
      case '已加入':
        statusColor = Colors.green;
        break;
      default:
        statusColor = Colors.grey;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 1.5,
        ),
      ),
      child: InkWell(
        onTap: () => _showActivityDetail(activity.id),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题和状态
              Row(
                children: [
                  Expanded(
                    child: Text(
                      activity.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? statusColor.withValues(alpha: 0.3)
                          : statusColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 11,
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 时间
              Row(
                children: [
                  Icon(
                    Icons.access_time,
                    size: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      startTime != null && endTime != null
                          ? '${dateFormat.format(startTime)} - ${dateFormat.format(endTime)}'
                          : '${activity.startTime} - ${activity.endTime}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // 俱乐部
              Row(
                children: [
                  Icon(
                    Icons.groups,
                    size: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      activity.clubName,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // 人数
              Row(
                children: [
                  Icon(
                    Icons.people,
                    size: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${activity.memberNum}/${activity.peopleNum}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // 地址提示
              Row(
                children: [
                  Icon(
                    Icons.location_on,
                    size: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '点击查看活动地址',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
              // 报名时间（可报名状态显示完整时间段）
              if (showApplyButton &&
                  activity.signUpStartTime.isNotEmpty &&
                  activity.signUpEndTime.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.schedule,
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '报名: ${activity.signUpStartTime} - ${activity.signUpEndTime}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              // 报名开始时间（未开始状态显示）
              if (statusLabel == '未开始' &&
                  activity.signUpStartTime.isNotEmpty) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.purple.withValues(alpha: 0.25)
                        : Colors.purple.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.schedule, size: 12, color: Colors.purple),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '报名开始: ${activity.signUpStartTime}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.purple,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // 签到状态（仅在我的活动中显示）
              if (showSignInStatus) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? (activity.isAllSigned
                              ? Colors.green.withValues(alpha: 0.25)
                              : (activity.signList != null &&
                                        activity.signList!.isNotEmpty
                                    ? Colors.orange.withValues(alpha: 0.25)
                                    : Colors.blue.withValues(alpha: 0.25)))
                        : (activity.isAllSigned
                              ? Colors.green.withValues(alpha: 0.15)
                              : (activity.signList != null &&
                                        activity.signList!.isNotEmpty
                                    ? Colors.orange.withValues(alpha: 0.15)
                                    : Colors.blue.withValues(alpha: 0.15))),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        activity.isAllSigned
                            ? Icons.check_circle
                            : (activity.signList != null &&
                                      activity.signList!.isNotEmpty
                                  ? Icons.pending
                                  : Icons.info_outline),
                        size: 12,
                        color: activity.isAllSigned
                            ? Colors.green
                            : (activity.signList != null &&
                                      activity.signList!.isNotEmpty
                                  ? Colors.orange
                                  : (Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Colors.blue.shade300
                                        : Colors.blue)),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        activity.signInStatus,
                        style: TextStyle(
                          fontSize: 11,
                          color: activity.isAllSigned
                              ? Colors.green
                              : (activity.signList != null &&
                                        activity.signList!.isNotEmpty
                                    ? Colors.orange
                                    : (Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? Colors.blue.shade300
                                          : Colors.blue)),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // 已加入状态
              if (showJoinedStatus) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.green.withValues(alpha: 0.25)
                        : Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.green.withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 18,
                        color: Colors.green,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '已加入',
                        style: TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // 报名按钮
              if (showApplyButton) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _handleApply(activity.id),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('报名'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 显示活动详情
  Future<void> _showActivityDetail(String activityId) async {
    final provider = Provider.of<LaborClubProvider>(context, listen: false);

    // 显示加载对话框
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
                Text('正在加载活动详情...'),
              ],
            ),
          ),
        ),
      ),
    );

    // 获取活动详情
    final detail = await provider.getActivityDetail(activityId);

    if (!mounted) return;

    // 关闭加载对话框
    Navigator.of(context).pop();

    if (detail == null) {
      // 获取失败
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('获取活动详情失败')));
      return;
    }

    // 显示详情底部弹窗
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildActivityDetailSheet(detail),
    );
  }

  /// 构建活动详情底部弹窗
  Widget _buildActivityDetailSheet(ActivityDetail detail) {
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');

    DateTime? startTime;
    DateTime? endTime;
    try {
      startTime = DateTime.parse(detail.startTime);
      endTime = DateTime.parse(detail.endTime);
    } catch (e) {
      // 时间解析失败
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // 拖动指示器
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // 标题栏
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '活动详情',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // 详情内容
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    // 活动标题
                    Text(
                      detail.title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 基本信息
                    _buildDetailInfoRow(
                      Icons.access_time,
                      '活动时间',
                      startTime != null && endTime != null
                          ? '${dateFormat.format(startTime)}\n至 ${dateFormat.format(endTime)}'
                          : '${detail.startTime}\n至 ${detail.endTime}',
                    ),
                    const SizedBox(height: 12),
                    _buildDetailInfoRow(
                      Icons.location_on,
                      '活动地点',
                      detail.location.isNotEmpty ? detail.location : '未指定',
                    ),
                    const SizedBox(height: 12),
                    _buildDetailInfoRow(Icons.groups, '俱乐部', detail.clubName),
                    const SizedBox(height: 12),
                    _buildDetailInfoRow(
                      Icons.person,
                      '负责人',
                      detail.chargeUserName,
                    ),
                    const SizedBox(height: 12),
                    _buildDetailInfoRow(
                      Icons.people,
                      '报名人数',
                      '${detail.memberNum}/${detail.peopleNum}',
                    ),
                    // 报名时间
                    if (detail.signUpStartTime != null &&
                        detail.signUpEndTime != null) ...[
                      const SizedBox(height: 12),
                      _buildDetailInfoRow(
                        Icons.schedule,
                        '报名时间',
                        '${detail.signUpStartTime}\n至 ${detail.signUpEndTime}',
                      ),
                    ],

                    // 签到状态
                    if (detail.signList.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text(
                        '签到记录',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? (detail.isAllSigned
                                    ? Colors.green.withValues(alpha: 0.2)
                                    : Colors.orange.withValues(alpha: 0.2))
                              : (detail.isAllSigned
                                    ? Colors.green.withValues(alpha: 0.1)
                                    : Colors.orange.withValues(alpha: 0.1)),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: detail.isAllSigned
                                ? Colors.green
                                : Colors.orange,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              detail.isAllSigned
                                  ? Icons.check_circle
                                  : Icons.pending,
                              color: detail.isAllSigned
                                  ? Colors.green
                                  : Colors.orange,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                detail.signInStatus,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: detail.isAllSigned
                                      ? Colors.green
                                      : Colors.orange,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...detail.signList.map(
                        (sign) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Theme.of(
                                  context,
                                ).colorScheme.outlineVariant,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '签到',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? (sign.isSigned
                                                  ? Colors.green.withValues(
                                                      alpha: 0.3,
                                                    )
                                                  : Colors.grey.withValues(
                                                      alpha: 0.3,
                                                    ))
                                            : (sign.isSigned
                                                  ? Colors.green.withValues(
                                                      alpha: 0.2,
                                                    )
                                                  : Colors.grey.withValues(
                                                      alpha: 0.2,
                                                    )),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        sign.statusText,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: sign.isSigned
                                              ? Colors.green
                                              : Colors.grey,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.access_time,
                                      size: 14,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${sign.startTime} - ${sign.endTime}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                                if (sign.signTime != null &&
                                    sign.signTime!.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.check,
                                        size: 14,
                                        color: Colors.green,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '签到时间: ${sign.signTime}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(color: Colors.green),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.blue.withValues(alpha: 0.2)
                              : Colors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? Colors.blue.shade300
                                : Colors.blue,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.blue.shade300
                                  : Colors.blue,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '默认签到',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color:
                                      Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.blue.shade300
                                      : Colors.blue,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // 表单数据
                    if (detail.formData.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text(
                        '详细信息',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      ...detail.formData.map((field) {
                        if (field.name.isEmpty || field.value.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _buildDetailInfoRow(
                            Icons.info_outline,
                            field.name,
                            field.value,
                          ),
                        );
                      }),
                    ],

                    // 审批流程
                    if (detail.flowData.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text(
                        '审批流程',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      ...detail.flowData.map(
                        (flow) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Theme.of(
                                  context,
                                ).colorScheme.outlineVariant,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        flow.nodeName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      flow.isAdopt == true ? '已通过' : '待审批',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '审批人: ${flow.userName}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                if (flow.time.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    '时间: ${flow.time}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],

                    // 教师列表
                    if (detail.teacherList.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text(
                        '相关教师',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      ...detail.teacherList.map(
                        (teacher) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              const Icon(Icons.person, size: 16),
                              const SizedBox(width: 8),
                              Text(teacher.name),
                              const SizedBox(width: 8),
                              Text(
                                teacher.userNo,
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
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 构建详情信息行
  Widget _buildDetailInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 20,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(value, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }

  /// 处理报名
  Future<void> _handleApply(String activityId) async {
    // 显示确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认报名'),
        content: const Text('确定要报名这个活动吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // 显示加载对话框
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
                Text('正在报名...'),
              ],
            ),
          ),
        ),
      ),
    );

    // 调用报名接口
    final provider = Provider.of<LaborClubProvider>(context, listen: false);
    final success = await provider.applyActivity(activityId);

    if (!mounted) return;

    // 关闭加载对话框
    Navigator.of(context).pop();

    // 显示结果
    if (success) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
          title: const Text('报名成功'),
          content: const Text('您已成功报名该活动'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.error, color: Colors.red, size: 48),
          title: const Text('报名失败'),
          content: const Text('报名失败，请稍后重试'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    }
  }
}
