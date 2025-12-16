import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' show LinearProgressIndicator, AlwaysStoppedAnimation;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/labor_club/labor_club_activity.dart';
import '../../models/labor_club/labor_club_info.dart';
import '../../models/labor_club/activity_detail.dart';
import '../../providers/labor_club_provider.dart';
import '../widgets/winui_card.dart';
import '../widgets/winui_loading.dart';
import '../widgets/winui_empty_state.dart';
import '../widgets/winui_dialogs.dart';

/// WinUI 风格的劳动俱乐部页面
///
/// 桌面端布局：左侧进度+俱乐部 | 右侧活动列表/详情
/// 复用 LaborClubProvider 进行数据管理
class WinUILaborClubPage extends StatefulWidget {
  const WinUILaborClubPage({super.key});

  @override
  State<WinUILaborClubPage> createState() => _WinUILaborClubPageState();
}

class _WinUILaborClubPageState extends State<WinUILaborClubPage> {
  /// 当前选中的活动
  LaborClubActivity? _selectedActivity;

  /// 活动详情
  ActivityDetail? _activityDetail;

  /// 是否正在加载详情
  bool _loadingDetail = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    final provider = Provider.of<LaborClubProvider?>(context, listen: false);
    if (provider == null) return;
    
    await provider.loadData(forceRefresh: forceRefresh);

    if (mounted && provider.state == LaborClubState.error) {
      _showErrorDialog(provider.errorMessage ?? '加载失败', provider.isRetryable);
    }
  }

  Future<void> _refreshData() async {
    setState(() {
      _selectedActivity = null;
      _activityDetail = null;
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

  Future<void> _loadActivityDetail(LaborClubActivity activity) async {
    setState(() {
      _selectedActivity = activity;
      _loadingDetail = true;
      _activityDetail = null;
    });

    final provider = Provider.of<LaborClubProvider?>(context, listen: false);
    if (provider == null) return;
    
    final detail = await provider.getActivityDetail(activity.id);

    if (mounted) {
      setState(() {
        _activityDetail = detail;
        _loadingDetail = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LaborClubProvider?>(
      builder: (context, provider, child) {
        // Provider 为 null 时显示加载状态
        if (provider == null) {
          return const ScaffoldPage(
            header: PageHeader(title: Text('劳动俱乐部')),
            content: WinUILoading(message: '正在初始化...'),
          );
        }

        return ScaffoldPage(
          header: PageHeader(
            title: const Text('劳动俱乐部'),
            commandBar: CommandBar(
              mainAxisAlignment: MainAxisAlignment.end,
              primaryItems: [
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

  Widget _buildContent(BuildContext context, LaborClubProvider provider) {
    if (provider.state == LaborClubState.loading) {
      return const WinUILoading(message: '正在加载劳动俱乐部数据');
    }

    if (provider.state == LaborClubState.loaded) {
      return _buildMainLayout(context, provider);
    }

    if (provider.state == LaborClubState.error) {
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

  /// 桌面端主布局
  Widget _buildMainLayout(BuildContext context, LaborClubProvider provider) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左侧：进度 + 俱乐部
        SizedBox(
          width: 320,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildProgressCard(context, provider),
                const SizedBox(height: 16),
                _buildClubsCard(context, provider),
              ],
            ),
          ),
        ),
        Container(
          width: 1,
          color: FluentTheme.of(context).resources.controlStrokeColorDefault,
        ),
        // 右侧：活动列表或详情
        Expanded(
          child: _selectedActivity != null
              ? _buildActivityDetail(context, provider)
              : _buildActivitiesList(context, provider),
        ),
      ],
    );
  }


  /// 构建进度卡片
  Widget _buildProgressCard(BuildContext context, LaborClubProvider provider) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final progressInfo = provider.progressInfo;

    if (progressInfo == null) return const SizedBox.shrink();

    final isCompleted = progressInfo.isCompleted;
    final percentage = progressInfo.progressPercentage;
    final finishCount = progressInfo.finishCount;
    final remaining = 10 - finishCount;

    return WinUICard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(FluentIcons.task_list, size: 20, color: theme.accentColor),
              const SizedBox(width: 8),
              Text('劳动修课进度', style: theme.typography.subtitle),
              const Spacer(),
              _buildStatusBadge(
                context,
                isCompleted ? '已达标' : '未达标',
                isCompleted
                    ? (isDark ? Colors.green.light : Colors.green)
                    : (isDark ? Colors.orange.light : Colors.orange),
                isCompleted ? FluentIcons.check_mark : FluentIcons.warning,
              ),
            ],
          ),
          const SizedBox(height: 20),
          // 大数字显示
          Center(
            child: Column(
              children: [
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: '$finishCount',
                        style: theme.typography.display?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.accentColor,
                        ),
                      ),
                      TextSpan(
                        text: ' / 10',
                        style: theme.typography.title?.copyWith(
                          color: theme.inactiveColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text('已完成次数', style: theme.typography.caption?.copyWith(color: theme.inactiveColor)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 进度条 - 使用自定义进度条确保正确显示
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: LinearProgressIndicator(
                value: percentage / 100,
                backgroundColor: theme.inactiveColor.withValues(alpha: 0.2),
                valueColor: AlwaysStoppedAnimation<Color>(
                  isCompleted
                      ? (isDark ? Colors.green.light : Colors.green)
                      : theme.accentColor,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${percentage.toStringAsFixed(0)}%', style: theme.typography.caption?.copyWith(color: theme.inactiveColor)),
              if (!isCompleted)
                Text(
                  '还需 $remaining 次',
                  style: theme.typography.caption?.copyWith(
                    color: isDark ? Colors.orange.light : Colors.orange,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建俱乐部卡片
  Widget _buildClubsCard(BuildContext context, LaborClubProvider provider) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final clubs = provider.clubs ?? [];

    return WinUICard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(FluentIcons.people, size: 20, color: theme.accentColor),
              const SizedBox(width: 8),
              Text('已加入俱乐部', style: theme.typography.subtitle),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${clubs.length}',
                  style: TextStyle(fontSize: 11, color: theme.accentColor, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          if (clubs.isEmpty) ...[
            const SizedBox(height: 16),
            Center(
              child: Text('暂未加入任何俱乐部', style: theme.typography.body?.copyWith(color: theme.inactiveColor)),
            ),
          ] else ...[
            const SizedBox(height: 12),
            ...clubs.map((club) => _buildClubItem(context, club, isDark)),
          ],
        ],
      ),
    );
  }

  Widget _buildClubItem(BuildContext context, LaborClubInfo club, bool isDark) {
    final theme = FluentTheme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.resources.controlStrokeColorDefault),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: (isDark ? Colors.teal.light : Colors.teal).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(FluentIcons.group, size: 18, color: isDark ? Colors.teal.light : Colors.teal),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  club.name,
                  style: theme.typography.body?.copyWith(fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${club.memberNum} 人',
                  style: theme.typography.caption?.copyWith(color: theme.inactiveColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  /// 构建活动列表
  Widget _buildActivitiesList(BuildContext context, LaborClubProvider provider) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final ongoingActivities = provider.ongoingActivities;
    final availableActivities = provider.availableActivities;
    final finishedActivities = provider.finishedActivities;
    final fullActivities = provider.fullActivities;

    final hasAnyActivity = ongoingActivities.isNotEmpty ||
        availableActivities.isNotEmpty ||
        finishedActivities.isNotEmpty ||
        fullActivities.isNotEmpty;

    if (!hasAnyActivity) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(FluentIcons.calendar, size: 64, color: theme.inactiveColor),
            const SizedBox(height: 16),
            Text('暂无活动', style: theme.typography.subtitle?.copyWith(color: theme.inactiveColor)),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 待开始（已报名）
          if (ongoingActivities.isNotEmpty)
            _buildActivityGroup(
              context,
              '待开始',
              '已报名的活动',
              ongoingActivities,
              FluentIcons.event_accepted,
              isDark ? Colors.teal.light : Colors.teal,
              provider,
              showSignStatus: true,
            ),
          // 可报名
          if (availableActivities.isNotEmpty)
            _buildActivityGroup(
              context,
              '可报名',
              '立即报名参加',
              availableActivities,
              FluentIcons.add_event,
              isDark ? Colors.blue.light : Colors.blue,
              provider,
              showApplyButton: true,
            ),
          // 已满员
          if (fullActivities.isNotEmpty)
            _buildActivityGroup(
              context,
              '已满员',
              '名额已满',
              fullActivities,
              FluentIcons.blocked,
              isDark ? Colors.orange.light : Colors.orange,
              provider,
            ),
          // 已结束
          if (finishedActivities.isNotEmpty)
            _buildActivityGroup(
              context,
              '已结束',
              '历史活动记录',
              finishedActivities,
              FluentIcons.history,
              isDark ? Colors.grey[100] : Colors.grey,
              provider,
              showSignStatus: true,
            ),
        ],
      ),
    );
  }

  Widget _buildActivityGroup(
    BuildContext context,
    String title,
    String subtitle,
    List<LaborClubActivity> activities,
    IconData icon,
    Color color,
    LaborClubProvider provider, {
    bool showSignStatus = false,
    bool showApplyButton = false,
  }) {
    final theme = FluentTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 分组标题
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title, style: theme.typography.subtitle),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${activities.length}',
                          style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  Text(subtitle, style: theme.typography.caption?.copyWith(color: theme.inactiveColor)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 活动卡片列表
        ...activities.map((activity) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _buildActivityListItem(
            context,
            activity,
            color,
            provider,
            showSignStatus: showSignStatus,
            showApplyButton: showApplyButton,
          ),
        )),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildActivityListItem(
    BuildContext context,
    LaborClubActivity activity,
    Color accentColor,
    LaborClubProvider provider, {
    bool showSignStatus = false,
    bool showApplyButton = false,
  }) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isSelected = _selectedActivity?.id == activity.id;

    return HoverButton(
      onPressed: () => _loadActivityDetail(activity),
      builder: (context, states) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: states.isHovering
                ? accentColor.withValues(alpha: 0.08)
                : (isSelected ? accentColor.withValues(alpha: 0.12) : null),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? accentColor : theme.resources.controlStrokeColorDefault,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              // 活动信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activity.title,
                      style: theme.typography.body?.copyWith(fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(FluentIcons.clock, size: 12, color: theme.inactiveColor),
                        const SizedBox(width: 4),
                        Text(
                          _formatTime(activity.startTime),
                          style: theme.typography.caption?.copyWith(color: theme.inactiveColor),
                        ),
                        const SizedBox(width: 12),
                        Icon(FluentIcons.people, size: 12, color: theme.inactiveColor),
                        const SizedBox(width: 4),
                        Text(
                          '${activity.memberNum}/${activity.peopleNum}',
                          style: theme.typography.caption?.copyWith(color: theme.inactiveColor),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      activity.clubName,
                      style: theme.typography.caption?.copyWith(color: theme.inactiveColor),
                    ),
                  ],
                ),
              ),
              // 右侧状态/按钮
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (showSignStatus && activity.signList != null && activity.signList!.isNotEmpty)
                    _buildStatusBadge(
                      context,
                      activity.isAllSigned ? '已签到' : '待签到',
                      activity.isAllSigned
                          ? (isDark ? Colors.green.light : Colors.green)
                          : (isDark ? Colors.orange.light : Colors.orange),
                      activity.isAllSigned ? FluentIcons.check_mark : FluentIcons.clock,
                    ),
                  if (showApplyButton && !provider.isActivityJoined(activity.id)) ...[
                    const SizedBox(height: 4),
                    FilledButton(
                      onPressed: () => _applyActivity(activity, provider),
                      child: const Text('报名'),
                    ),
                  ],
                  if (!showSignStatus && !showApplyButton)
                    Icon(FluentIcons.chevron_right, size: 12, color: theme.inactiveColor),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusBadge(BuildContext context, String text, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Future<void> _applyActivity(LaborClubActivity activity, LaborClubProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('确认报名'),
        content: Text('确认报名活动「${activity.title}」？'),
        actions: [
          Button(child: const Text('取消'), onPressed: () => Navigator.of(context).pop(false)),
          FilledButton(child: const Text('确认'), onPressed: () => Navigator.of(context).pop(true)),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await provider.applyActivity(activity.id);
      if (mounted) {
        if (success) {
          displayInfoBar(context, builder: (context, close) => InfoBar(title: const Text('报名成功'), severity: InfoBarSeverity.success, onClose: close));
        } else {
          displayInfoBar(context, builder: (context, close) => InfoBar(title: const Text('报名失败'), severity: InfoBarSeverity.error, onClose: close));
        }
      }
    }
  }


  /// 构建活动详情面板
  Widget _buildActivityDetail(BuildContext context, LaborClubProvider provider) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_loadingDetail) {
      return const WinUILoading(message: '加载详情中');
    }

    final activity = _selectedActivity!;
    final detail = _activityDetail;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 返回按钮
          Button(
            onPressed: () => setState(() {
              _selectedActivity = null;
              _activityDetail = null;
            }),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(FluentIcons.back, size: 14),
                SizedBox(width: 8),
                Text('返回列表'),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // 活动标题卡片
          WinUICard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: theme.accentColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(FluentIcons.event, size: 24, color: theme.accentColor),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(activity.title, style: theme.typography.title),
                          const SizedBox(height: 4),
                          Text(activity.clubName, style: theme.typography.body?.copyWith(color: theme.inactiveColor)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 时间和人数
          Row(
            children: [
              Expanded(
                child: WinUICard(
                  child: Column(
                    children: [
                      Icon(FluentIcons.calendar, size: 24, color: isDark ? Colors.blue.light : Colors.blue),
                      const SizedBox(height: 8),
                      Text(_formatTime(activity.startTime), style: theme.typography.bodyStrong),
                      Text('开始时间', style: theme.typography.caption?.copyWith(color: theme.inactiveColor)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: WinUICard(
                  child: Column(
                    children: [
                      Icon(FluentIcons.calendar, size: 24, color: isDark ? Colors.orange.light : Colors.orange),
                      const SizedBox(height: 8),
                      Text(_formatTime(activity.endTime), style: theme.typography.bodyStrong),
                      Text('结束时间', style: theme.typography.caption?.copyWith(color: theme.inactiveColor)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: WinUICard(
                  child: Column(
                    children: [
                      Icon(FluentIcons.people, size: 24, color: isDark ? Colors.teal.light : Colors.teal),
                      const SizedBox(height: 8),
                      Text('${activity.memberNum}/${activity.peopleNum}', style: theme.typography.bodyStrong),
                      Text('报名人数', style: theme.typography.caption?.copyWith(color: theme.inactiveColor)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 详细信息
          WinUICard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('活动信息', style: theme.typography.bodyStrong),
                const SizedBox(height: 16),
                _buildDetailRow(context, '负责人', activity.chargeUserName),
                const SizedBox(height: 10),
                if (detail?.location.isNotEmpty == true) ...[
                  _buildDetailRow(context, '活动地点', detail!.location),
                  const SizedBox(height: 10),
                ],
                _buildDetailRow(context, '活动状态', _getActivityStatus(activity)),
              ],
            ),
          ),
          // 签到记录
          if (activity.signList != null && activity.signList!.isNotEmpty) ...[
            const SizedBox(height: 16),
            WinUICard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('签到记录', style: theme.typography.bodyStrong),
                      const Spacer(),
                      _buildStatusBadge(
                        context,
                        activity.isAllSigned ? '全部完成' : '${activity.signList!.where((s) => s.isSign).length}/${activity.signList!.length}',
                        activity.isAllSigned
                            ? (isDark ? Colors.green.light : Colors.green)
                            : (isDark ? Colors.orange.light : Colors.orange),
                        activity.isAllSigned ? FluentIcons.check_mark : FluentIcons.clock,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ...activity.signList!.map((sign) => _buildSignItem(context, sign, isDark)),
                ],
              ),
            ),
          ],
          // 报名按钮
          if (!provider.isActivityJoined(activity.id) && activity.memberNum < activity.peopleNum) ...[
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => _applyActivity(activity, provider),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('立即报名'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSignItem(BuildContext context, dynamic sign, bool isDark) {
    final theme = FluentTheme.of(context);
    final isSign = sign.isSign;
    final color = isSign ? (isDark ? Colors.green.light : Colors.green) : (isDark ? Colors.orange.light : Colors.orange);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            isSign ? FluentIcons.check_mark : FluentIcons.clock,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sign.typeName, style: theme.typography.body?.copyWith(fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(
                  '${_formatTime(sign.startTime)} - ${_formatTime(sign.endTime)}',
                  style: theme.typography.caption?.copyWith(color: theme.inactiveColor),
                ),
              ],
            ),
          ),
          Text(
            isSign ? '已签到' : '未签到',
            style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, String label, String value) {
    final theme = FluentTheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 70,
          child: Text(label, style: theme.typography.body?.copyWith(color: theme.inactiveColor)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(value, style: theme.typography.body?.copyWith(fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }

  String _formatTime(String timeStr) {
    try {
      final dt = DateTime.parse(timeStr);
      return DateFormat('MM-dd HH:mm').format(dt);
    } catch (e) {
      return timeStr;
    }
  }

  String _getActivityStatus(LaborClubActivity activity) {
    final now = DateTime.now();
    try {
      final start = DateTime.parse(activity.startTime);
      final end = DateTime.parse(activity.endTime);
      if (now.isBefore(start)) return '未开始';
      if (now.isAfter(end)) return '已结束';
      return '进行中';
    } catch (e) {
      return '未知';
    }
  }
}
