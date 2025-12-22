import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/jwc/course_schedule_record.dart';
import '../../models/jwc/plan_category.dart';
import '../../models/jwc/plan_course.dart';
import '../../models/jwc/plan_option.dart';
import '../../models/jwc/student_schedule.dart';
import '../../providers/auth_provider.dart';
import '../../providers/smart_course_selection_provider.dart';
import '../widgets/winui_card.dart';
import '../widgets/winui_loading.dart';
import '../widgets/winui_empty_state.dart';

/// WinUI 风格的智能排课页面
///
/// 功能：
/// - 左侧：预设管理区
/// - 中间：课程表视图（显示已有课程和模拟选课）
/// - 右侧上方：课程详情和模拟选课/退课按钮
/// - 右侧下方：可选课程列表（培养方案未完成且开课的课程）
class WinUISmartCourseSelectionPage extends StatefulWidget {
  const WinUISmartCourseSelectionPage({super.key});

  @override
  State<WinUISmartCourseSelectionPage> createState() =>
      _WinUISmartCourseSelectionPageState();
}

class _WinUISmartCourseSelectionPageState
    extends State<WinUISmartCourseSelectionPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeData();
    });
  }

  Future<void> _initializeData() async {
    final provider =
        Provider.of<SmartCourseSelectionProvider?>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (provider == null) return;

    final userId = authProvider.credentials?.userId ?? '';
    await provider.initialize(userId);
  }

  Future<void> _refreshCourseData() async {
    final provider =
        Provider.of<SmartCourseSelectionProvider?>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (provider == null) return;

    final userId = authProvider.credentials?.userId ?? '';
    await provider.refreshCourseData(userId);
  }

  String _formatRefreshTime(DateTime? time) {
    if (time == null) return '从未刷新';
    return DateFormat('MM-dd HH:mm').format(time);
  }

  /// 构建 CommandBar 按钮列表
  List<CommandBarItem> _buildCommandBarItems(
      BuildContext context, SmartCourseSelectionProvider provider) {
    final items = <CommandBarItem>[];

    // 如果是多培养方案用户且已加载完成，显示切换按钮
    if (provider.hasMultiplePlans &&
        provider.state == SmartCourseSelectionState.loaded) {
      items.add(CommandBarButton(
        icon: const Icon(FluentIcons.switch_widget),
        label: const Text('切换培养方案'),
        onPressed: () => provider.backToPlanSelection(),
      ));
    }

    items.add(CommandBarButton(
      icon: const Icon(FluentIcons.refresh),
      label: const Text('刷新开课数据'),
      onPressed: provider.state == SmartCourseSelectionState.loading
          ? null
          : _refreshCourseData,
    ));

    items.add(CommandBarButton(
      icon: const Icon(FluentIcons.add),
      label: const Text('新建选课表'),
      onPressed: () async {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        final userId = authProvider.credentials?.userId ?? '';
        await provider.newSelectionTable(userId);
      },
    ));

    return items;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SmartCourseSelectionProvider?>(
      builder: (context, provider, child) {
        if (provider == null) {
          return const ScaffoldPage(
            header: PageHeader(title: Text('智能排课')),
            content: WinUILoading(message: '正在初始化...'),
          );
        }

        return ScaffoldPage(
          header: _buildHeader(context, provider),
          content: _buildContent(context, provider),
        );
      },
    );
  }

  Widget _buildHeader(
      BuildContext context, SmartCourseSelectionProvider provider) {
    final theme = FluentTheme.of(context);

    return PageHeader(
      title: Row(
        children: [
          const Text('智能排课'),
          const SizedBox(width: 16),
          // 学期选择
          if (provider.termList != null && provider.termList!.isNotEmpty)
            ComboBox<String>(
              value: provider.selectedTermCode,
              items: provider.termList!
                  .map((t) => ComboBoxItem<String>(
                        value: t.termCode,
                        child: Text(t.termName),
                      ))
                  .toList(),
              onChanged: (value) async {
                if (value != null) {
                  final authProvider =
                      Provider.of<AuthProvider>(context, listen: false);
                  final userId = authProvider.credentials?.userId ?? '';
                  await provider.selectTerm(value, userId);
                }
              },
            ),
          const SizedBox(width: 16),
          // 刷新时间
          Text(
            '开课数据: ${_formatRefreshTime(provider.courseDataRefreshTime)}',
            style: theme.typography.caption?.copyWith(
              color: theme.inactiveColor,
            ),
          ),
        ],
      ),
      commandBar: CommandBar(
        mainAxisAlignment: MainAxisAlignment.end,
        primaryItems: _buildCommandBarItems(context, provider),
      ),
    );
  }

  Widget _buildContent(
      BuildContext context, SmartCourseSelectionProvider provider) {
    // 加载中（带进度显示）
    if (provider.state == SmartCourseSelectionState.loading) {
      return _buildLoadingWithProgress(context, provider);
    }

    // 需要选择培养方案状态（多培养方案用户）
    if (provider.state == SmartCourseSelectionState.needPlanSelection) {
      return _buildPlanSelectionView(context, provider);
    }

    // 错误状态
    if (provider.state == SmartCourseSelectionState.error) {
      return WinUIEmptyState.needRefresh(
        title: '数据加载失败',
        description: provider.errorMessage ?? '请点击刷新重新加载',
        onAction: _initializeData,
      );
    }

    // 初始状态
    if (provider.state == SmartCourseSelectionState.initial) {
      return WinUIEmptyState.noData(
        title: '暂无数据',
        description: '正在初始化...',
      );
    }

    // 加载完成 - 三栏布局
    return Column(
      children: [
        // 课表变化提示
        if (provider.scheduleChanged) _buildScheduleChangeWarning(context, provider),
        // 主内容
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左侧：培养方案树 + 预设管理
              SizedBox(
                width: 320,
                child: _buildLeftPanel(context, provider),
              ),
              Container(
                width: 1,
                color: FluentTheme.of(context).resources.controlStrokeColorDefault,
              ),
              // 中间：课程表（自适应宽度）
              Expanded(
                child: _buildScheduleView(context, provider),
              ),
              Container(
                width: 1,
                color: FluentTheme.of(context).resources.controlStrokeColorDefault,
              ),
              // 右侧：课程信息面板（始终显示）
              SizedBox(
                width: 360,
                child: _buildSidePanel(context, provider),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 构建课表变化警告
  Widget _buildScheduleChangeWarning(
      BuildContext context, SmartCourseSelectionProvider provider) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: (isDark ? Colors.orange.light : Colors.orange).withValues(alpha: 0.15),
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.orange.light : Colors.orange,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            FluentIcons.warning,
            color: isDark ? Colors.orange.light : Colors.orange,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '检测到课表变化',
                  style: theme.typography.bodyStrong?.copyWith(
                    color: isDark ? Colors.orange.light : Colors.orange,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '新增 ${provider.addedToSchedule.length} 门课程，移除 ${provider.removedFromSchedule.length} 门课程',
                  style: theme.typography.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Button(
            child: const Text('接受变化'),
            onPressed: () async {
              final authProvider =
                  Provider.of<AuthProvider>(context, listen: false);
              final userId = authProvider.credentials?.userId ?? '';
              await provider.acceptScheduleChanges(userId);
            },
          ),
          const SizedBox(width: 8),
          Button(
            child: const Text('忽略'),
            onPressed: () => provider.ignoreScheduleChanges(),
          ),
          const SizedBox(width: 8),
          Button(
            child: const Text('重新开始'),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => ContentDialog(
                  title: const Text('重新开始选课'),
                  content: const Text('这将清除所有模拟选课/退课记录，以当前课表为基准重新开始。确定吗？'),
                  actions: [
                    Button(
                      child: const Text('取消'),
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                    FilledButton(
                      child: const Text('确定'),
                      onPressed: () => Navigator.of(context).pop(true),
                    ),
                  ],
                ),
              );
              if (confirmed == true && context.mounted) {
                final authProvider =
                    Provider.of<AuthProvider>(context, listen: false);
                final userId = authProvider.credentials?.userId ?? '';
                await provider.resetSelection(userId);
              }
            },
          ),
        ],
      ),
    );
  }

  /// 构建带进度的加载界面
  Widget _buildLoadingWithProgress(
      BuildContext context, SmartCourseSelectionProvider provider) {
    final theme = FluentTheme.of(context);
    final progress = provider.loadingProgress;
    final hasProgress = provider.loadingProgressTotal > 0;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 进度环或普通加载环
          SizedBox(
            width: 80,
            height: 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (hasProgress)
                  SizedBox(
                    width: 80,
                    height: 80,
                    child: ProgressRing(
                      value: progress * 100,
                      strokeWidth: 6,
                    ),
                  )
                else
                  const SizedBox(
                    width: 60,
                    height: 60,
                    child: ProgressRing(strokeWidth: 4),
                  ),
                if (hasProgress)
                  Text(
                    '${(progress * 100).toInt()}%',
                    style: theme.typography.bodyStrong?.copyWith(
                      color: theme.accentColor,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // 加载消息
          Text(
            provider.loadingMessage,
            style: theme.typography.body,
            textAlign: TextAlign.center,
          ),
          if (hasProgress) ...[
            const SizedBox(height: 8),
            Text(
              '已获取 ${provider.loadingProgressRecords} 条记录',
              style: theme.typography.caption?.copyWith(
                color: theme.inactiveColor,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 构建右侧面板（课程详情 + 可选课程列表）
  Widget _buildSidePanel(
      BuildContext context, SmartCourseSelectionProvider provider) {
    return Column(
      children: [
        // 课程详情（始终显示，无选中时显示提示）
        Expanded(
          flex: 2,
          child: _buildCourseDetail(context, provider),
        ),
        Container(
          height: 1,
          color: FluentTheme.of(context).resources.controlStrokeColorDefault,
        ),
        // 可选课程列表
        Expanded(
          flex: 3,
          child: _buildAvailableCoursesList(context, provider),
        ),
      ],
    );
  }

  /// 构建左侧面板（培养方案树 + 可折叠预设管理）
  Widget _buildLeftPanel(
      BuildContext context, SmartCourseSelectionProvider provider) {
    return Column(
      children: [
        // 培养方案树（主要区域）
        Expanded(
          child: _buildPlanTreeView(context, provider),
        ),
        Container(
          height: 1,
          color: FluentTheme.of(context).resources.controlStrokeColorDefault,
        ),
        // 底部：可折叠的预设管理
        _buildCollapsiblePresetPanel(context, provider),
      ],
    );
  }


  /// 构建可折叠的预设管理面板
  Widget _buildCollapsiblePresetPanel(
      BuildContext context, SmartCourseSelectionProvider provider) {
    final theme = FluentTheme.of(context);

    return Expander(
      initiallyExpanded: false,
      header: Row(
        children: [
          Icon(FluentIcons.favorite_list, size: 14, color: theme.accentColor),
          const SizedBox(width: 8),
          Text('预设管理', style: theme.typography.bodyStrong),
          const Spacer(),
          if (provider.presets.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${provider.presets.length}',
                style: theme.typography.caption?.copyWith(
                  color: theme.accentColor,
                  fontSize: 10,
                ),
              ),
            ),
        ],
      ),
      content: Column(
        children: [
          // 操作按钮行
          Row(
            children: [
              Expanded(
                child: Button(
                  onPressed: () => _showSavePresetDialog(context, provider),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(FluentIcons.save, size: 12),
                      SizedBox(width: 4),
                      Text('保存'),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Button(
                  onPressed: () async {
                    final authProvider =
                        Provider.of<AuthProvider>(context, listen: false);
                    final userId = authProvider.credentials?.userId ?? '';
                    await provider.newSelectionTable(userId);
                  },
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(FluentIcons.add, size: 12),
                      SizedBox(width: 4),
                      Text('新建'),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (provider.presets.isNotEmpty) ...[
            const SizedBox(height: 8),
            // 预设列表（紧凑版）
            ...provider.presets.map((preset) {
              final isSelected =
                  provider.selectionData?.currentPresetId == preset.id;
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: ListTile.selectable(
                  selected: isSelected,
                  title: Text(preset.name, style: theme.typography.caption),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${preset.selectedCourses.length}门',
                        style: theme.typography.caption?.copyWith(
                          color: theme.inactiveColor,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: Icon(FluentIcons.delete, size: 12, color: Colors.red),
                        onPressed: () async {
                          final authProvider =
                              Provider.of<AuthProvider>(context, listen: false);
                          final userId = authProvider.credentials?.userId ?? '';
                          await provider.deletePreset(preset.id, userId);
                        },
                      ),
                    ],
                  ),
                  onPressed: () async {
                    final authProvider =
                        Provider.of<AuthProvider>(context, listen: false);
                    final userId = authProvider.credentials?.userId ?? '';
                    await provider.loadPreset(preset.id, userId);
                  },
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  /// 显示保存预设对话框
  Future<void> _showSavePresetDialog(
      BuildContext context, SmartCourseSelectionProvider provider) async {
    final controller = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ContentDialog(
        title: const Text('保存预设'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('请输入预设名称：'),
            const SizedBox(height: 8),
            TextBox(
              controller: controller,
              placeholder: '预设名称',
              autofocus: true,
            ),
          ],
        ),
        actions: [
          Button(
            child: const Text('取消'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          FilledButton(
            child: const Text('保存'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );

    if (result == true && controller.text.isNotEmpty && mounted) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userId = authProvider.credentials?.userId ?? '';
      await provider.savePreset(controller.text, userId);
    }

    controller.dispose();
  }

  /// 构建课程表视图
  Widget _buildScheduleView(
      BuildContext context, SmartCourseSelectionProvider provider) {
    final theme = FluentTheme.of(context);
    final schedule = provider.studentSchedule;

    return Column(
      children: [
        // 标题栏
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(FluentIcons.calendar, size: 16, color: theme.accentColor),
              const SizedBox(width: 8),
              Text('课程表', style: theme.typography.subtitle),
              const Spacer(),
              if (schedule != null)
                Text(
                  '已选 ${provider.getEffectiveSelectedCourses().length} 门课程，'
                  '共 ${_calculateEffectiveCredits(provider)} 学分'
                  '${provider.removedCourses.isNotEmpty ? " (退${provider.removedCourses.length}门)" : ""}'
                  '${provider.currentSelectedCourses.isNotEmpty ? " (加${provider.currentSelectedCourses.length}门)" : ""}',
                  style: theme.typography.caption?.copyWith(
                    color: theme.inactiveColor,
                  ),
                ),
            ],
          ),
        ),
        const Divider(),
        // 课程表网格
        Expanded(
          child: _buildScheduleGrid(context, provider),
        ),
      ],
    );
  }

  double _calculateSimulatedCredits(SmartCourseSelectionProvider provider) {
    double credits = 0;
    for (final key in provider.currentSelectedCourses) {
      final course = provider.availableCourses.firstWhere(
        (c) => '${c.kch}_${c.kxh}' == key,
        orElse: () => CourseScheduleRecord(),
      );
      credits += course.xf ?? 0;
    }
    return credits;
  }

  /// 计算有效学分（原始课表 - 退课 + 新增）
  double _calculateEffectiveCredits(SmartCourseSelectionProvider provider) {
    double credits = 0;

    // 原始课表学分（排除已退课的）
    if (provider.studentSchedule != null) {
      for (final course in provider.studentSchedule!.courses) {
        final courseKey = '${course.courseCode}_${course.courseSequence}';
        if (!provider.removedCourses.contains(courseKey)) {
          credits += course.unit;
        }
      }
    }

    // 新增课程学分
    credits += _calculateSimulatedCredits(provider);

    return credits;
  }

  /// 构建课程表网格
  Widget _buildScheduleGrid(
      BuildContext context, SmartCourseSelectionProvider provider) {
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    const sessions = 10; // 10节课（删除11-12节）
    const double cellHeight = 52.0; // 适中的单元格高度
    const double headerHeight = 32.0;
    const double sessionColumnWidth = 28.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth - sessionColumnWidth;
          final cellWidth = availableWidth / 7;

          return SizedBox(
            height: headerHeight + cellHeight * sessions,
            child: Stack(
              children: [
                // 背景网格
                _buildGridBackground(
                  context,
                  weekdays,
                  sessions,
                  cellWidth,
                  cellHeight,
                  headerHeight,
                  sessionColumnWidth,
                ),
                // 课程卡片
                ..._buildCourseCards(
                  context,
                  provider,
                  cellWidth,
                  cellHeight,
                  headerHeight,
                  sessionColumnWidth,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 构建网格背景
  Widget _buildGridBackground(
    BuildContext context,
    List<String> weekdays,
    int sessions,
    double cellWidth,
    double cellHeight,
    double headerHeight,
    double sessionColumnWidth,
  ) {
    final theme = FluentTheme.of(context);
    final borderColor = theme.resources.controlStrokeColorDefault;

    return Column(
      children: [
        // 表头行
        Container(
          height: headerHeight,
          decoration: BoxDecoration(
            color: theme.accentColor.withValues(alpha: 0.1),
            border: Border(bottom: BorderSide(color: borderColor)),
          ),
          child: Row(
            children: [
              Container(
                width: sessionColumnWidth,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: borderColor)),
                ),
                child: Text('节', style: theme.typography.bodyStrong),
              ),
              ...weekdays.map((d) => Container(
                    width: cellWidth,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border(right: BorderSide(color: borderColor)),
                    ),
                    child: Text(d, style: theme.typography.bodyStrong),
                  )),
            ],
          ),
        ),
        // 节次行
        for (int session = 1; session <= sessions; session++)
          Container(
            height: cellHeight,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            child: Row(
              children: [
                Container(
                  width: sessionColumnWidth,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border(right: BorderSide(color: borderColor)),
                  ),
                  child: Text('$session', style: theme.typography.caption),
                ),
                for (int day = 1; day <= 7; day++)
                  GestureDetector(
                    onTap: () {
                      final provider = Provider.of<SmartCourseSelectionProvider>(context, listen: false);
                      provider.selectTimeSlot(day, session);
                      provider.selectCourse(null); // 清除选中的课程
                    },
                    child: Builder(
                      builder: (context) {
                        final provider = Provider.of<SmartCourseSelectionProvider>(context);
                        final isSelected = provider.selectedDay == day && provider.selectedSession == session;
                        return Container(
                          width: cellWidth,
                          decoration: BoxDecoration(
                            color: isSelected ? theme.accentColor.withValues(alpha: 0.1) : null,
                            border: Border(right: BorderSide(color: borderColor)),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  /// 构建课程卡片列表
  List<Widget> _buildCourseCards(
    BuildContext context,
    SmartCourseSelectionProvider provider,
    double cellWidth,
    double cellHeight,
    double headerHeight,
    double sessionColumnWidth,
  ) {
    final cards = <Widget>[];

    // 已有课程（排除已退课的）
    if (provider.studentSchedule != null) {
      for (final course in provider.studentSchedule!.courses) {
        final courseKey = '${course.courseCode}_${course.courseSequence}';
        // 跳过已退课的课程
        if (provider.removedCourses.contains(courseKey)) continue;

        for (final tp in course.timeAndPlaceList) {
          final left = sessionColumnWidth + (tp.classDay - 1) * cellWidth;
          final top = headerHeight + (tp.classSessions - 1) * cellHeight;
          final height = tp.continuingSession * cellHeight;

          cards.add(Positioned(
            left: left + 2,
            top: top + 2,
            width: cellWidth - 4,
            height: height - 4,
            child: _buildExistingCourseCard(context, course, tp, provider),
          ));
        }
      }
    }

    // 模拟选课（新增的课程）
    for (final key in provider.currentSelectedCourses) {
      final course = provider.availableCourses.firstWhere(
        (c) => '${c.kch}_${c.kxh}' == key,
        orElse: () => CourseScheduleRecord(),
      );

      if (course.skxq == null || course.skjc == null) continue;

      final left = sessionColumnWidth + (course.skxq! - 1) * cellWidth;
      final top = headerHeight + (course.skjc! - 1) * cellHeight;
      final continuingSession = course.cxjc ?? 1;
      final height = continuingSession * cellHeight;

      cards.add(Positioned(
        left: left + 2,
        top: top + 2,
        width: cellWidth - 4,
        height: height - 4,
        child: _buildSimulatedCourseCard(context, course, provider),
      ));
    }

    return cards;
  }

  /// 构建已有课程卡片
  Widget _buildExistingCourseCard(
    BuildContext context,
    ScheduleCourse course,
    ScheduleTimePlace tp,
    SmartCourseSelectionProvider provider,
  ) {
    final theme = FluentTheme.of(context);

    return GestureDetector(
      onTap: () {
        // 更新选中的时间段，让右下角课程列表显示该时间段的课程
        provider.selectTimeSlot(tp.classDay, tp.classSessions);
        // 优先从 availableCourses 中查找完整的课程记录（包含 bkskyl 等字段）
        final fullRecord = provider.availableCourses.firstWhere(
          (c) => c.kch == course.courseCode && c.kxh == course.courseSequence,
          orElse: () => CourseScheduleRecord(
            kch: course.courseCode,
            kxh: course.courseSequence,
            kcm: course.courseName,
            xf: course.unit.toInt(),
            skjs: course.attendClassTeacher,
            xqm: tp.campusName,
            jxlm: tp.teachingBuildingName,
            jasm: tp.classroomName,
            skxq: tp.classDay,
            skjc: tp.classSessions,
            cxjc: tp.continuingSession,
            zcsm: tp.weekDescription,
          ),
        );
        provider.selectCourse(fullRecord);
      },
      child: Container(
        decoration: BoxDecoration(
          color: theme.accentColor.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: theme.accentColor.withValues(alpha: 0.5)),
        ),
        padding: const EdgeInsets.all(3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              course.courseName,
              style: theme.typography.caption?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 10,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const Spacer(),
            if (tp.classroomName.isNotEmpty)
              Text(
                tp.classroomName,
                style: theme.typography.caption?.copyWith(
                  fontSize: 9,
                  color: theme.inactiveColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }

  /// 构建模拟选课卡片
  Widget _buildSimulatedCourseCard(
    BuildContext context,
    CourseScheduleRecord course,
    SmartCourseSelectionProvider provider,
  ) {
    final theme = FluentTheme.of(context);

    return GestureDetector(
      onTap: () {
        // 更新选中的时间段，让右下角课程列表显示该时间段的课程
        if (course.skxq != null && course.skjc != null) {
          provider.selectTimeSlot(course.skxq!, course.skjc!);
        }
        provider.selectCourse(course);
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
        ),
        padding: const EdgeInsets.all(3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    course.kcm ?? '',
                    style: theme.typography.caption?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                      fontSize: 10,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(FluentIcons.add_event, size: 10, color: Colors.green),
              ],
            ),
            const Spacer(),
            Text(
              course.jasm ?? '',
              style: theme.typography.caption?.copyWith(
                fontSize: 8,
                color: theme.inactiveColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  /// 构建课程详情
  Widget _buildCourseDetail(
      BuildContext context, SmartCourseSelectionProvider provider) {
    final theme = FluentTheme.of(context);
    final course = provider.selectedCourse;

    if (course == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(FluentIcons.info, size: 40, color: theme.inactiveColor),
            const SizedBox(height: 16),
            Text(
              '点击课程表或下方列表\n查看课程详情',
              textAlign: TextAlign.center,
              style: theme.typography.body?.copyWith(color: theme.inactiveColor),
            ),
          ],
        ),
      );
    }

    final courseKey = '${course.kch}_${course.kxh}';
    final isNewlySelected = provider.currentSelectedCourses.contains(courseKey);
    final isFromOriginalSchedule = provider.isCourseFromOriginalSchedule(courseKey);
    final isRemoved = provider.removedCourses.contains(courseKey);
    final hasConflict = provider.checkConflict(course);
    final isPassed = provider.isCoursePassed(course.kch);
    final score = provider.getCourseScore(course.kch);
    final isDark = theme.brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 课程名称
          Row(
            children: [
              Expanded(
                child: Text(
                  course.kcm ?? '未知课程',
                  style: theme.typography.subtitle?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (isPassed)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.teal.light : Colors.teal).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(FluentIcons.check_mark, size: 12, color: isDark ? Colors.teal.light : Colors.teal),
                      const SizedBox(width: 4),
                      Text(
                        '已修${score != null ? " $score" : ""}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.teal.light : Colors.teal,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // 培养方案路径
          if (provider.getCoursePlanPath(course.kch) != null)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.accentColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Icon(FluentIcons.folder, size: 12, color: theme.accentColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      provider.getCoursePlanPath(course.kch)!,
                      style: theme.typography.caption?.copyWith(
                        color: theme.accentColor,
                        fontSize: 10,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          // 课程信息
          _buildDetailRow(context, '课程号', course.kch ?? ''),
          _buildDetailRow(context, '课序号', course.kxh ?? ''),
          _buildDetailRow(context, '学分', '${course.xf ?? 0}'),
          _buildDetailRow(context, '教师', course.skjs ?? ''),
          _buildDetailRow(context, '校区', course.xqm ?? ''),
          _buildDetailRow(context, '教室', '${course.jxlm ?? ''} ${course.jasm ?? ''}'),
          _buildDetailRow(context, '时间', course.scheduleDescription),
          _buildDetailRow(context, '容量', '${course.bkskrl ?? 0} / 余量: ${_getActualCapacity(course)}'),
          const SizedBox(height: 12),
          // 冲突提示
          if (hasConflict && !isNewlySelected && !isFromOriginalSchedule && !isPassed)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.orange),
              ),
              child: Row(
                children: [
                  Icon(FluentIcons.warning, size: 16, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '该课程与已有课程时间冲突',
                      style: TextStyle(color: Colors.orange),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          // 操作按钮
          if (!isPassed)
            Row(
              children: [
                Expanded(
                  child: _buildCourseActionButton(
                    context,
                    provider,
                    courseKey,
                    isNewlySelected: isNewlySelected,
                    isFromOriginalSchedule: isFromOriginalSchedule,
                    isRemoved: isRemoved,
                    hasConflict: hasConflict,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// 获取实际课余量数值（支持负数表示超选情况）
  int _getActualCapacityInt(CourseScheduleRecord course) {
    // 如果有课余量字段，直接使用（可能为负数）
    if (course.bkskyl != null) {
      return course.bkskyl!;
    }
    // 如果有容量和学生数，计算课余量
    if (course.bkskrl != null && course.xss != null) {
      return course.bkskrl! - course.xss!;
    }
    // 默认返回0
    return 0;
  }

  /// 获取实际课余量字符串（支持负数显示超选情况）
  String _getActualCapacity(CourseScheduleRecord course) {
    return '${_getActualCapacityInt(course)}';
  }

  Widget _buildDetailRow(BuildContext context, String label, String value) {
    final theme = FluentTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: theme.typography.caption?.copyWith(
                color: theme.inactiveColor,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.typography.caption,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建课程操作按钮
  Widget _buildCourseActionButton(
    BuildContext context,
    SmartCourseSelectionProvider provider,
    String courseKey, {
    required bool isNewlySelected,
    required bool isFromOriginalSchedule,
    required bool isRemoved,
    required bool hasConflict,
  }) {
    // 情况1：新增的课程 -> 显示"模拟退课"
    if (isNewlySelected) {
      return Button(
        style: ButtonStyle(
          backgroundColor:
              WidgetStateProperty.all(Colors.red.withValues(alpha: 0.1)),
        ),
        onPressed: () async {
          final authProvider =
              Provider.of<AuthProvider>(context, listen: false);
          final userId = authProvider.credentials?.userId ?? '';
          await provider.removeCourse(courseKey, userId);
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(FluentIcons.remove, size: 14, color: Colors.red),
            const SizedBox(width: 8),
            Text('模拟退课', style: TextStyle(color: Colors.red)),
          ],
        ),
      );
    }

    // 情况2：原始课表中的课程（未被退课）-> 显示"模拟退课"
    if (isFromOriginalSchedule) {
      return Button(
        style: ButtonStyle(
          backgroundColor:
              WidgetStateProperty.all(Colors.orange.withValues(alpha: 0.1)),
        ),
        onPressed: () async {
          final authProvider =
              Provider.of<AuthProvider>(context, listen: false);
          final userId = authProvider.credentials?.userId ?? '';
          await provider.removeCourse(courseKey, userId);
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(FluentIcons.remove, size: 14, color: Colors.orange),
            const SizedBox(width: 8),
            Text('模拟退课（原有）', style: TextStyle(color: Colors.orange)),
          ],
        ),
      );
    }

    // 情况3：已被退课的课程 -> 显示"恢复选课"
    if (isRemoved) {
      return FilledButton(
        onPressed: hasConflict
            ? null
            : () async {
                final authProvider =
                    Provider.of<AuthProvider>(context, listen: false);
                final userId = authProvider.credentials?.userId ?? '';
                await provider.addCourse(courseKey, userId);
              },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(FluentIcons.undo, size: 14),
            const SizedBox(width: 8),
            Text(hasConflict ? '有冲突，无法恢复' : '恢复选课'),
          ],
        ),
      );
    }

    // 情况4：未选中的课程 -> 显示"模拟选课"
    return FilledButton(
      onPressed: hasConflict
          ? null
          : () async {
              final authProvider =
                  Provider.of<AuthProvider>(context, listen: false);
              final userId = authProvider.credentials?.userId ?? '';
              await provider.addCourse(courseKey, userId);
            },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(FluentIcons.add, size: 14),
          const SizedBox(width: 8),
          Text(hasConflict ? '有冲突，无法选课' : '模拟选课'),
        ],
      ),
    );
  }

  /// 构建可选课程列表（显示选中时间段的可选课程）
  Widget _buildAvailableCoursesList(
      BuildContext context, SmartCourseSelectionProvider provider) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final selectedDay = provider.selectedDay;
    final selectedSession = provider.selectedSession;

    // 获取选中时间段的可选课程
    List<CourseScheduleRecord> courses = [];
    String title = '可选课程';
    
    if (selectedDay != null && selectedSession != null) {
      courses = provider.getCoursesForTimeSlot(selectedDay, selectedSession);
      const weekdays = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];
      title = '${weekdays[selectedDay]} 第$selectedSession节 可选课程';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题栏
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(FluentIcons.library, size: 16, color: theme.accentColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title, style: theme.typography.subtitle),
              ),
              if (courses.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${courses.length} 门',
                    style: theme.typography.caption?.copyWith(
                      color: Colors.green,
                    ),
                  ),
                ),
            ],
          ),
        ),
        // 筛选控件
        _buildFilterControls(context, provider),
        const Divider(),
        // 课程列表
        Expanded(
          child: selectedDay == null || selectedSession == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(FluentIcons.touch_pointer, size: 40, color: theme.inactiveColor),
                      const SizedBox(height: 16),
                      Text(
                        '点击课程表空白处\n查看该时间段可选课程',
                        textAlign: TextAlign.center,
                        style: theme.typography.body?.copyWith(
                          color: theme.inactiveColor,
                        ),
                      ),
                    ],
                  ),
                )
              : courses.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(FluentIcons.sad, size: 40, color: theme.inactiveColor),
                          const SizedBox(height: 16),
                          Text(
                            '该时间段暂无可选课程',
                            textAlign: TextAlign.center,
                            style: theme.typography.body?.copyWith(
                              color: theme.inactiveColor,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: courses.length,
                      itemBuilder: (context, index) {
                        final course = courses[index];
                        final isSelected = provider.currentSelectedCourses
                            .contains('${course.kch}_${course.kxh}');
                        final hasConflict = provider.checkConflict(course);
                        final planPath = provider.getCoursePlanPath(course.kch);
                        final isPassed = provider.isCoursePassed(course.kch);
                        final score = provider.getCourseScore(course.kch);

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: ListTile.selectable(
                            selected: provider.selectedCourse?.kch == course.kch &&
                                provider.selectedCourse?.kxh == course.kxh,
                            leading: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isPassed
                                    ? (isDark ? Colors.teal.light : Colors.teal)
                                    : (isSelected
                                        ? Colors.green
                                        : (hasConflict ? Colors.orange : Colors.grey)),
                              ),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    course.kcm ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: isPassed
                                        ? theme.typography.body?.copyWith(
                                            color: theme.inactiveColor,
                                          )
                                        : null,
                                  ),
                                ),
                                if (isPassed)
                                  Container(
                                    margin: const EdgeInsets.only(left: 8),
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: (isDark ? Colors.teal.light : Colors.teal).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '已修${score != null ? " $score" : ""}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: isDark ? Colors.teal.light : Colors.teal,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${course.kxh ?? ''} | ${course.skjs ?? ''} | ${course.xqm ?? ''}',
                                  style: theme.typography.caption?.copyWith(
                                    color: isPassed ? theme.inactiveColor : null,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (planPath != null)
                                  Text(
                                    planPath,
                                    style: theme.typography.caption?.copyWith(
                                      color: isPassed
                                          ? theme.inactiveColor
                                          : (isDark ? Colors.blue.light : Colors.blue),
                                      fontSize: 10,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${course.xf ?? 0}学分',
                                  style: theme.typography.caption?.copyWith(
                                    color: isPassed ? theme.inactiveColor : null,
                                  ),
                                ),
                                if (!isPassed)
                                  Text(
                                    '余${_getActualCapacity(course)}',
                                    style: theme.typography.caption?.copyWith(
                                      color: _getActualCapacityInt(course) > 0
                                          ? (isDark ? Colors.green.light : Colors.green)
                                          : Colors.red,
                                      fontSize: 10,
                                    ),
                                  ),
                              ],
                            ),
                            onPressed: () {
                              provider.selectCourse(course);
                            },
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  /// 构建筛选控件
  Widget _buildFilterControls(
      BuildContext context, SmartCourseSelectionProvider provider) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final campuses = provider.allCampuses;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.resources.subtleFillColorSecondary,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行：校区筛选
          Row(
            children: [
              Icon(FluentIcons.filter, size: 12, color: theme.inactiveColor),
              const SizedBox(width: 6),
              Text('校区:', style: theme.typography.caption),
              const SizedBox(width: 8),
              Expanded(
                child: ComboBox<String?>(
                  value: provider.filterCampus,
                  placeholder: const Text('全部校区'),
                  isExpanded: true,
                  items: [
                    const ComboBoxItem<String?>(
                      value: null,
                      child: Text('全部校区'),
                    ),
                    ...campuses.map((c) => ComboBoxItem<String?>(
                          value: c,
                          child: Text(c),
                        )),
                  ],
                  onChanged: (value) {
                    provider.setFilter(campus: value ?? '');
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 第二行：开关筛选
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              // 隐藏已修
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ToggleSwitch(
                    checked: provider.filterHidePassed,
                    onChanged: (value) {
                      provider.setFilter(hidePassed: value);
                    },
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '隐藏已修',
                    style: theme.typography.caption?.copyWith(
                      color: provider.filterHidePassed
                          ? (isDark ? Colors.teal.light : Colors.teal)
                          : theme.inactiveColor,
                    ),
                  ),
                ],
              ),
              // 隐藏已完成分类
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ToggleSwitch(
                    checked: provider.filterHideCompletedCategory,
                    onChanged: (value) {
                      provider.setFilter(hideCompletedCategory: value);
                    },
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '隐藏已完成分类',
                    style: theme.typography.caption?.copyWith(
                      color: provider.filterHideCompletedCategory
                          ? (isDark ? Colors.teal.light : Colors.teal)
                          : theme.inactiveColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建培养方案树视图
  Widget _buildPlanTreeView(
      BuildContext context, SmartCourseSelectionProvider provider) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final planInfo = provider.planCompletion;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题栏
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(FluentIcons.education, size: 14, color: theme.accentColor),
              const SizedBox(width: 6),
              Text('培养方案', style: theme.typography.bodyStrong),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${provider.availableUncompletedCoursesCount} 门本学期可选',
                  style: theme.typography.caption?.copyWith(
                    color: isDark ? Colors.green.light : Colors.green,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(),
        // 培养方案树
        Expanded(
          child: planInfo == null
              ? Center(
                  child: Text(
                    '暂无培养方案',
                    style: theme.typography.caption?.copyWith(
                      color: theme.inactiveColor,
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: planInfo.categories
                        .map((cat) => _buildPlanCategoryNode(context, provider, cat))
                        .toList(),
                  ),
                ),
        ),
      ],
    );
  }

  /// 构建培养方案分类节点
  Widget _buildPlanCategoryNode(
    BuildContext context,
    SmartCourseSelectionProvider provider,
    PlanCategory category,
  ) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // 计算该分类下有多少课程在当前学期有开课且未修
    int availableCount = 0;
    int totalUnpassed = 0;
    
    void countCourses(PlanCategory cat) {
      for (final course in cat.courses) {
        if (!course.isPassed) {
          totalUnpassed++;
          if (provider.isCourseAvailableInTerm(course.courseCode)) {
            availableCount++;
          }
        }
      }
      for (final sub in cat.subcategories) {
        countCourses(sub);
      }
    }
    countCourses(category);

    // 如果没有未通过的课程，显示已完成（但仍可展开查看）
    final isCompleted = totalUnpassed == 0 && category.courses.isNotEmpty;
    
    if (isCompleted && category.subcategories.isEmpty) {
      // 叶子节点且已完成，简单显示
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(FluentIcons.check_mark, size: 12, color: isDark ? Colors.green.light : Colors.green),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                category.categoryName,
                style: theme.typography.caption?.copyWith(
                  color: theme.inactiveColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: (isDark ? Colors.green.light : Colors.green).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                '已完成',
                style: TextStyle(
                  fontSize: 9,
                  color: isDark ? Colors.green.light : Colors.green,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Expander(
      initiallyExpanded: availableCount > 0,
      header: Row(
        children: [
          Icon(
            isCompleted ? FluentIcons.folder_fill : FluentIcons.folder,
            size: 12,
            color: isCompleted
                ? (isDark ? Colors.green.light : Colors.green)
                : (isDark ? Colors.orange.light : Colors.orange),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              category.categoryName,
              style: theme.typography.caption?.copyWith(
                color: isCompleted ? theme.inactiveColor : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (availableCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                '$availableCount可选',
                style: TextStyle(
                  fontSize: 9,
                  color: isDark ? Colors.green.light : Colors.green,
                ),
              ),
            )
          else if (isCompleted)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: (isDark ? Colors.green.light : Colors.green).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                '已完成',
                style: TextStyle(
                  fontSize: 9,
                  color: isDark ? Colors.green.light : Colors.green,
                ),
              ),
            ),
          const SizedBox(width: 4),
          Text(
            '${category.completedCredits}/${category.minCredits}',
            style: theme.typography.caption?.copyWith(
              color: theme.inactiveColor,
              fontSize: 10,
            ),
          ),
        ],
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 子分类
          ...category.subcategories.map<Widget>((sub) => Padding(
                padding: const EdgeInsets.only(left: 12),
                child: _buildPlanCategoryNode(context, provider, sub),
              )),
          // 课程列表（优先显示有开课的，然后显示未开课的，最后显示已修的）
          ...category.courses
              .where((course) => !course.isPassed && provider.isCourseAvailableInTerm(course.courseCode))
              .map<Widget>((course) => _buildPlanCourseNode(context, provider, course, status: 'available')),
          // 未开课的课程（灰色显示）
          ...category.courses
              .where((course) => !course.isPassed && !provider.isCourseAvailableInTerm(course.courseCode))
              .map<Widget>((course) => _buildPlanCourseNode(context, provider, course, status: 'unavailable')),
          // 已修的课程（绿色显示）
          ...category.courses
              .where((course) => course.isPassed)
              .map<Widget>((course) => _buildPlanCourseNode(context, provider, course, status: 'passed')),
        ],
      ),
    );
  }

  /// 构建培养方案课程节点
  /// status: 'available' - 有开课, 'unavailable' - 未开课, 'passed' - 已修
  Widget _buildPlanCourseNode(
    BuildContext context,
    SmartCourseSelectionProvider provider,
    PlanCourse course, {
    String status = 'available',
  }) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final scheduleRecords = provider.getCourseScheduleRecords(course.courseCode);
    final score = course.score;

    Color textColor;
    IconData icon;
    String trailingText;
    Color? bgColor;

    switch (status) {
      case 'available':
        textColor = isDark ? Colors.blue.light : Colors.blue;
        icon = FluentIcons.page;
        trailingText = '${scheduleRecords.length}班';
        bgColor = theme.accentColor.withValues(alpha: 0.05);
        break;
      case 'unavailable':
        textColor = theme.inactiveColor;
        icon = FluentIcons.clock;
        trailingText = '未开课';
        bgColor = theme.resources.subtleFillColorSecondary;
        break;
      case 'passed':
        textColor = isDark ? Colors.teal.light : Colors.teal;
        icon = FluentIcons.check_mark;
        trailingText = score != null ? '已修 $score' : '已修';
        bgColor = (isDark ? Colors.teal.light : Colors.teal).withValues(alpha: 0.08);
        break;
      default:
        textColor = theme.inactiveColor;
        icon = FluentIcons.page;
        trailingText = '';
        bgColor = null;
    }

    // 不可选的课程（未开课或已修）直接显示简单行
    if (status != 'available' || scheduleRecords.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(icon, size: 9, color: textColor),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  course.courseName.isNotEmpty ? course.courseName : course.courseCode,
                  style: theme.typography.caption?.copyWith(
                    color: textColor,
                    fontSize: 10,
                    height: 1.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                trailingText,
                style: theme.typography.caption?.copyWith(
                  color: status == 'passed' ? textColor : theme.inactiveColor,
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 有开课班级的课程，使用 Expander 展示所有班级
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 4),
      child: Expander(
        initiallyExpanded: false,
        headerBackgroundColor: WidgetStateProperty.all(bgColor ?? Colors.transparent),
        header: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 9, color: textColor),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                course.courseName.isNotEmpty ? course.courseName : course.courseCode,
                style: theme.typography.caption?.copyWith(
                  color: textColor,
                  fontSize: 10,
                  height: 1.2,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                trailingText,
                style: TextStyle(
                  fontSize: 9,
                  color: isDark ? Colors.green.light : Colors.green,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: scheduleRecords.map((record) {
            final isSelected = provider.currentSelectedCourses
                .contains('${record.kch}_${record.kxh}');
            final hasConflict = provider.checkConflict(record);
            
            return GestureDetector(
              onTap: () => provider.selectCourse(record),
              child: Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.green.withValues(alpha: 0.15)
                      : (hasConflict
                          ? Colors.orange.withValues(alpha: 0.1)
                          : theme.resources.subtleFillColorSecondary),
                  borderRadius: BorderRadius.circular(4),
                  border: isSelected
                      ? Border.all(color: Colors.green, width: 1)
                      : null,
                ),
                child: Row(
                  children: [
                    // 状态指示器
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected
                            ? Colors.green
                            : (hasConflict ? Colors.orange : theme.accentColor),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 班级信息
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '${record.kxh ?? ""}班',
                                style: theme.typography.caption?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  record.skjs ?? '',
                                  style: theme.typography.caption?.copyWith(
                                    color: theme.inactiveColor,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${record.xqm ?? ""} | ${record.scheduleDescription}',
                            style: theme.typography.caption?.copyWith(
                              fontSize: 10,
                              color: theme.inactiveColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    // 余量
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (isSelected)
                          Icon(FluentIcons.check_mark, size: 12, color: Colors.green)
                        else if (hasConflict)
                          Icon(FluentIcons.warning, size: 12, color: Colors.orange),
                        Text(
                          '余${_getActualCapacity(record)}',
                          style: theme.typography.caption?.copyWith(
                            fontSize: 9,
                            color: _getActualCapacityInt(record) > 0
                                ? (isDark ? Colors.green.light : Colors.green)
                                : Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  /// 构建培养方案选择视图（多培养方案用户）
  Widget _buildPlanSelectionView(BuildContext context, SmartCourseSelectionProvider provider) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final options = provider.planOptions;
    final hint = provider.planSelectionResponse?.hint;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 提示信息
              if (hint != null && hint.isNotEmpty)
                WinUICard(
                  child: Row(
                    children: [
                      Icon(
                        FluentIcons.info,
                        color: isDark ? Colors.blue.light : Colors.blue,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(hint, style: theme.typography.body),
                      ),
                    ],
                  ),
                ),
              if (hint != null && hint.isNotEmpty) const SizedBox(height: 16),

              // 说明卡片
              WinUICard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          FluentIcons.education,
                          color: theme.accentColor,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '选择培养方案',
                          style: theme.typography.subtitle,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '智能排课需要基于培养方案进行课程推荐，请选择要使用的培养方案',
                      style: theme.typography.body?.copyWith(
                        color: theme.inactiveColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // 培养方案选项列表
              ...options.map((option) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildPlanOptionCard(context, option, provider),
              )),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建培养方案选项卡片
  Widget _buildPlanOptionCard(BuildContext context, PlanOption option, SmartCourseSelectionProvider provider) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.credentials?.userId ?? '';

    // 根据方案类型选择颜色
    Color typeColor;
    IconData typeIcon;
    if (option.planType == '主修') {
      typeColor = isDark ? Colors.green.light : Colors.green;
      typeIcon = FluentIcons.education;
    } else if (option.planType == '辅修') {
      typeColor = isDark ? Colors.blue.light : Colors.blue;
      typeIcon = FluentIcons.library;
    } else {
      typeColor = isDark ? Colors.purple.light : Colors.purple;
      typeIcon = FluentIcons.certificate;
    }

    return HoverButton(
      onPressed: () => provider.selectPlanAndContinue(option.planId, userId),
      builder: (context, states) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: states.isHovered
              ? theme.resources.subtleFillColorSecondary
              : theme.resources.cardBackgroundFillColorDefault,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: states.isHovered
                ? theme.accentColor
                : theme.resources.controlStrokeColorDefault,
            width: states.isHovered ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // 方案类型图标
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: typeColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(typeIcon, color: typeColor, size: 24),
            ),
            const SizedBox(width: 16),

            // 方案信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.planName,
                    style: theme.typography.bodyStrong,
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
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          option.planType,
                          style: TextStyle(
                            fontSize: 11,
                            color: typeColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (option.isCurrent) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: (isDark ? Colors.green.light : Colors.green)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '当前使用',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.green.light : Colors.green,
                              fontWeight: FontWeight.w600,
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
              FluentIcons.chevron_right,
              color: theme.inactiveColor,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}
