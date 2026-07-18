import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/jwc/course_schedule_record.dart';
import '../../models/jwc/plan_category.dart';
import '../../models/jwc/plan_course.dart';
import '../../models/jwc/plan_option.dart';
import '../../models/jwc/student_schedule.dart';
import '../../providers/auth_provider.dart';
import '../../providers/smart_course_selection_provider.dart';
import '../../services/jwc/class_curriculum_service.dart';
import '../layout/schedule_card_layout.dart';
import '../widgets/winui_card.dart';
import '../widgets/winui_loading.dart';
import '../widgets/winui_empty_state.dart';
import '../mixins/user_scope_data_loader.dart';

const double _wideCourseSelectionBreakpoint = 1200;
const double _minimumScheduleGridWidth = 720;

/// 课程信息辅助类（用于选课清单）
class _CourseInfo {
  final String courseCode;
  final String courseSeq;
  final String courseName;
  final String teacher;
  final double credits;
  final String? schedule;

  _CourseInfo({
    required this.courseCode,
    required this.courseSeq,
    required this.courseName,
    required this.teacher,
    required this.credits,
    this.schedule,
  });
}

class _ClassCurriculumDialog extends StatefulWidget {
  final String termCode;
  final ClassCurriculumService service;

  const _ClassCurriculumDialog({required this.termCode, required this.service});

  @override
  State<_ClassCurriculumDialog> createState() => _ClassCurriculumDialogState();
}

class _ClassCurriculumDialogState extends State<_ClassCurriculumDialog> {
  var _departments = <ClassCurriculumOption>[];
  var _subjects = <ClassCurriculumOption>[];
  var _classes = <ClassCurriculumClassOption>[];
  ClassCurriculumOption? _selectedDepartment;
  ClassCurriculumOption? _selectedSubject;
  ClassCurriculumClassOption? _selectedClass;
  var _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadDepartments();
  }

  Future<void> _loadDepartments() async {
    final response = await widget.service.getDepartments();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (response.success && response.data != null) {
        _departments = response.data!;
      } else {
        _errorMessage = response.error ?? '获取学院失败';
      }
    });
  }

  Future<void> _loadSubjects(ClassCurriculumOption department) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _selectedDepartment = department;
      _selectedSubject = null;
      _selectedClass = null;
      _subjects = [];
      _classes = [];
    });

    final response = await widget.service.getSubjects(
      departmentCode: department.code,
    );
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (response.success && response.data != null) {
        _subjects = response.data!;
      } else {
        _errorMessage = response.error ?? '获取专业失败';
      }
    });
    await _loadClasses();
  }

  Future<void> _loadClasses() async {
    final department = _selectedDepartment;
    if (department == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _selectedClass = null;
      _classes = [];
    });

    final response = await widget.service.queryClasses(
      planCode: widget.termCode,
      departmentCode: department.code,
      subjectCode: _selectedSubject?.code,
    );
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (response.success && response.data != null) {
        _classes = response.data!;
      } else {
        _errorMessage = response.error ?? '获取班级失败';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      title: const Text('班级课表模式'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('当前学期：${widget.termCode}'),
            const SizedBox(height: 12),
            if (_errorMessage != null) ...[
              InfoBar(
                severity: InfoBarSeverity.error,
                title: Text(_errorMessage!),
              ),
              const SizedBox(height: 12),
            ],
            ComboBox<ClassCurriculumOption>(
              isExpanded: true,
              placeholder: const Text('选择学院'),
              value: _selectedDepartment,
              items: _departments
                  .map(
                    (item) => ComboBoxItem(value: item, child: Text(item.name)),
                  )
                  .toList(),
              onChanged: _isLoading || _departments.isEmpty
                  ? null
                  : (value) {
                      if (value != null) _loadSubjects(value);
                    },
            ),
            const SizedBox(height: 10),
            ComboBox<ClassCurriculumOption>(
              isExpanded: true,
              placeholder: const Text('选择专业（可选）'),
              value: _selectedSubject,
              items: _subjects
                  .map(
                    (item) => ComboBoxItem(value: item, child: Text(item.name)),
                  )
                  .toList(),
              onChanged: _selectedDepartment == null || _isLoading
                  ? null
                  : (value) {
                      setState(() => _selectedSubject = value);
                      _loadClasses();
                    },
            ),
            const SizedBox(height: 10),
            ComboBox<ClassCurriculumClassOption>(
              isExpanded: true,
              placeholder: const Text('选择班级'),
              value: _selectedClass,
              items: _classes
                  .map(
                    (item) =>
                        ComboBoxItem(value: item, child: Text(item.className)),
                  )
                  .toList(),
              onChanged: _isLoading
                  ? null
                  : (value) => setState(() => _selectedClass = value),
            ),
            if (_isLoading) ...[
              const SizedBox(height: 12),
              const ProgressBar(),
            ],
          ],
        ),
      ),
      actions: [
        Button(
          child: const Text('取消'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        FilledButton(
          onPressed: _selectedClass == null || _isLoading
              ? null
              : () => Navigator.of(context).pop(_selectedClass),
          child: const Text('切换'),
        ),
      ],
    );
  }
}

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
    extends State<WinUISmartCourseSelectionPage>
    with UserScopeDataLoader<WinUISmartCourseSelectionPage> {
  final TextEditingController _courseSearchController = TextEditingController();
  bool _showCourseFilters = false;
  int _compactViewIndex = 1;

  @override
  bool get isUserScopeReady =>
      Provider.of<SmartCourseSelectionProvider?>(context, listen: false) !=
      null;

  @override
  void loadUserScopeData() => _initializeData();

  @override
  void dispose() {
    _courseSearchController.dispose();
    super.dispose();
  }

  Future<void> _initializeData() async {
    if (!mounted) return;
    final provider = Provider.of<SmartCourseSelectionProvider?>(
      context,
      listen: false,
    );
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (provider == null) return;

    _courseSearchController.clear();
    provider.clearCourseSearch();
    final userId = authProvider.credentials?.userId ?? '';
    await provider.initialize(userId);
  }

  Future<void> _refreshCourseData() async {
    final provider = Provider.of<SmartCourseSelectionProvider?>(
      context,
      listen: false,
    );
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (provider == null) return;

    final userId = authProvider.credentials?.userId ?? '';
    await provider.refreshCourseData(userId);
  }

  Future<void> _switchToPersonalSchedule() async {
    final provider = Provider.of<SmartCourseSelectionProvider?>(
      context,
      listen: false,
    );
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (provider == null) return;

    final userId = authProvider.credentials?.userId ?? '';
    await provider.switchToPersonalSchedule(userId);
  }

  String _formatRefreshTime(DateTime? time) {
    if (time == null) return '从未刷新';
    return DateFormat('MM-dd HH:mm').format(time);
  }

  Future<void> _showClassCurriculumDialog(
    BuildContext context,
    SmartCourseSelectionProvider provider,
  ) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.credentials?.userId ?? '';
    final termCode = provider.selectedTermCode;
    if (termCode == null || termCode.isEmpty) return;

    final selectedClass = await showDialog<ClassCurriculumClassOption>(
      context: context,
      builder: (_) => _ClassCurriculumDialog(
        termCode: termCode,
        service: provider.jwcService.classCurriculum,
      ),
    );

    if (selectedClass == null || !context.mounted) return;
    await provider.useClassCurriculum(
      userId: userId,
      planCode: selectedClass.planCode,
      classCode: selectedClass.classCode,
      className: selectedClass.className,
    );
  }

  /// 构建 CommandBar 按钮列表
  List<CommandBarItem> _buildCommandBarItems(
    BuildContext context,
    SmartCourseSelectionProvider provider,
  ) {
    final items = <CommandBarItem>[];

    // 如果是多培养方案用户且已加载完成，显示切换按钮
    if (provider.hasMultiplePlans &&
        provider.state == SmartCourseSelectionState.loaded) {
      items.add(
        CommandBarButton(
          icon: const Icon(FluentIcons.switch_widget),
          label: const Text('切换培养方案'),
          onPressed: () => provider.backToPlanSelection(),
        ),
      );
    }

    // 选课清单按钮（有变化时显示）
    if (provider.state == SmartCourseSelectionState.loaded &&
        (provider.currentSelectedCourses.isNotEmpty ||
            provider.removedCourses.isNotEmpty)) {
      items.add(
        CommandBarButton(
          icon: const Icon(FluentIcons.clipboard_list),
          label: const Text('选课清单'),
          onPressed: () => _showSelectionSummaryDialog(context, provider),
        ),
      );
    }

    items.add(
      CommandBarButton(
        icon: const Icon(FluentIcons.refresh),
        label: const Text('刷新开课数据'),
        onPressed: provider.state == SmartCourseSelectionState.loading
            ? null
            : _refreshCourseData,
      ),
    );

    items.add(
      CommandBarButton(
        icon: const Icon(FluentIcons.switcher_start_end),
        label: Text(provider.usingClassCurriculum ? '个人课表模式' : '班级课表模式'),
        onPressed: provider.state == SmartCourseSelectionState.loading
            ? null
            : () async {
                if (provider.usingClassCurriculum) {
                  await _switchToPersonalSchedule();
                } else {
                  await _showClassCurriculumDialog(context, provider);
                }
              },
      ),
    );

    items.add(
      CommandBarButton(
        icon: const Icon(FluentIcons.reset),
        label: const Text('重置课表'),
        onPressed: provider.state == SmartCourseSelectionState.loading
            ? null
            : () => _showResetConfirmDialog(context, provider),
      ),
    );

    return items;
  }

  /// 显示重置课表确认对话框
  Future<void> _showResetConfirmDialog(
    BuildContext context,
    SmartCourseSelectionProvider provider,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('重置课表'),
        content: const Text('这将清除所有模拟选课/退课记录，以当前实际课表为基准重新开始。确定吗？'),
        actions: [
          Button(
            child: const Text('取消'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          FilledButton(
            child: const Text('确定重置'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userId = authProvider.credentials?.userId ?? '';
      await provider.resetSelection(userId);
    }
  }

  /// 显示选课清单对话框
  Future<void> _showSelectionSummaryDialog(
    BuildContext context,
    SmartCourseSelectionProvider provider,
  ) async {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // 获取退课列表
    final removedCourses = <_CourseInfo>[];
    for (final key in provider.removedCourses) {
      final parts = key.split('_');
      if (parts.length >= 2) {
        final courseCode = parts[0];
        final courseSeq = parts[1];
        // 从原始课表中查找课程信息
        ScheduleCourse? course;
        CourseScheduleRecord? classCourse;
        try {
          if (provider.usingClassCurriculum) {
            classCourse = provider.classCurriculumCourses.firstWhere(
              (c) => c.kch == courseCode && c.kxh == courseSeq,
            );
          } else {
            course = provider.studentSchedule?.courses.firstWhere(
              (c) =>
                  c.courseCode == courseCode && c.courseSequence == courseSeq,
            );
          }
        } catch (_) {
          course = null;
          classCourse = null;
        }
        removedCourses.add(
          _CourseInfo(
            courseCode: courseCode,
            courseSeq: courseSeq,
            courseName: classCourse?.kcm ?? course?.courseName ?? '未知课程',
            teacher: classCourse?.skjs ?? course?.attendClassTeacher ?? '',
            credits: (classCourse?.xf ?? course?.unit ?? 0).toDouble(),
            schedule: classCourse?.scheduleDescription,
          ),
        );
      }
    }

    // 获取新增选课列表
    final addedCourses = <_CourseInfo>[];
    for (final key in provider.currentSelectedCourses) {
      final records = provider.getAvailableCourseRecordsByKey(key);
      final course = records.isNotEmpty
          ? records.first
          : CourseScheduleRecord();
      if (course.kch != null) {
        addedCourses.add(
          _CourseInfo(
            courseCode: course.kch!,
            courseSeq: course.kxh ?? '',
            courseName: course.kcm ?? '未知课程',
            teacher: course.skjs ?? '',
            credits: (course.xf ?? 0).toDouble(),
            schedule: records
                .map((record) => record.scheduleDescription)
                .where((description) => description.isNotEmpty)
                .join('；'),
          ),
        );
      }
    }

    // 获取保持不变的课程列表
    final unchangedCourses = <_CourseInfo>[];
    if (provider.usingClassCurriculum) {
      for (final course in provider.classCurriculumCourses) {
        final courseKey = '${course.kch}_${course.kxh}';
        if (!provider.removedCourses.contains(courseKey)) {
          unchangedCourses.add(
            _CourseInfo(
              courseCode: course.kch ?? '',
              courseSeq: course.kxh ?? '',
              courseName: course.kcm ?? '未知课程',
              teacher: course.skjs ?? '',
              credits: (course.xf ?? 0).toDouble(),
              schedule: course.scheduleDescription,
            ),
          );
        }
      }
    } else if (provider.studentSchedule != null) {
      for (final course in provider.studentSchedule!.courses) {
        final courseKey = '${course.courseCode}_${course.courseSequence}';
        if (!provider.removedCourses.contains(courseKey)) {
          unchangedCourses.add(
            _CourseInfo(
              courseCode: course.courseCode,
              courseSeq: course.courseSequence,
              courseName: course.courseName,
              teacher: course.attendClassTeacher,
              credits: course.unit,
            ),
          );
        }
      }
    }

    // 生成文本清单
    String generateTextSummary() {
      final buffer = StringBuffer();
      buffer.writeln('===== 选课清单 =====');
      buffer.writeln();

      if (removedCourses.isNotEmpty) {
        buffer.writeln('【需要退课】');
        for (final c in removedCourses) {
          buffer.writeln(
            '${c.courseCode}\t${c.courseSeq}\t${c.courseName}\t${c.credits}学分',
          );
        }
        buffer.writeln();
      }

      if (addedCourses.isNotEmpty) {
        buffer.writeln('【需要选课】');
        for (final c in addedCourses) {
          buffer.writeln(
            '${c.courseCode}\t${c.courseSeq}\t${c.courseName}\t${c.teacher}\t${c.credits}学分',
          );
        }
        buffer.writeln();
      }

      if (unchangedCourses.isNotEmpty) {
        buffer.writeln('【保持不变】');
        for (final c in unchangedCourses) {
          buffer.writeln(
            '${c.courseCode}\t${c.courseSeq}\t${c.courseName}\t${c.credits}学分',
          );
        }
      }

      return buffer.toString();
    }

    await showDialog(
      context: context,
      builder: (context) => ContentDialog(
        title: Row(
          children: [
            Icon(FluentIcons.clipboard_list, color: theme.accentColor),
            const SizedBox(width: 8),
            const Text('选课清单'),
            const Spacer(),
            Button(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(FluentIcons.copy, size: 14),
                  const SizedBox(width: 6),
                  const Text('复制全部'),
                ],
              ),
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: generateTextSummary()),
                );
                if (context.mounted) {
                  displayInfoBar(
                    context,
                    builder: (context, close) {
                      return const InfoBar(
                        title: Text('已复制到剪贴板'),
                        severity: InfoBarSeverity.success,
                      );
                    },
                  );
                }
              },
            ),
          ],
        ),
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 500),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 退课列表
              if (removedCourses.isNotEmpty) ...[
                _buildSectionHeader(
                  context,
                  '需要退课',
                  Colors.red,
                  removedCourses.length,
                ),
                const SizedBox(height: 8),
                ...removedCourses.map(
                  (c) => _buildCourseRow(context, c, Colors.red, isDark),
                ),
                const SizedBox(height: 16),
              ],

              // 选课列表
              if (addedCourses.isNotEmpty) ...[
                _buildSectionHeader(
                  context,
                  '需要选课',
                  Colors.green,
                  addedCourses.length,
                ),
                const SizedBox(height: 8),
                ...addedCourses.map(
                  (c) => _buildCourseRow(context, c, Colors.green, isDark),
                ),
                const SizedBox(height: 16),
              ],

              // 无变化提示
              if (removedCourses.isEmpty && addedCourses.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(
                          FluentIcons.check_mark,
                          size: 48,
                          color: Colors.green,
                        ),
                        const SizedBox(height: 12),
                        Text('没有选课变化', style: theme.typography.subtitle),
                      ],
                    ),
                  ),
                ),

              // 保持不变的课程
              if (unchangedCourses.isNotEmpty) ...[
                _buildSectionHeader(
                  context,
                  '保持不变',
                  Colors.grey,
                  unchangedCourses.length,
                ),
                const SizedBox(height: 8),
                ...unchangedCourses.map(
                  (c) => _buildCourseRow(
                    context,
                    c,
                    Colors.grey,
                    isDark,
                    compact: true,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          FilledButton(
            child: const Text('关闭'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  /// 获取深色模式下的亮色变体
  Color _getLightVariant(Color color, bool isDark) {
    if (!isDark) return color;
    // 在深色模式下使用更亮的颜色
    final hsl = HSLColor.fromColor(color);
    return hsl.withLightness((hsl.lightness + 0.2).clamp(0.0, 1.0)).toColor();
  }

  /// 构建清单分类标题
  Widget _buildSectionHeader(
    BuildContext context,
    String title,
    Color color,
    int count,
  ) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final displayColor = _getLightVariant(color, isDark);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: displayColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(
            title.contains('退')
                ? FluentIcons.remove
                : title.contains('选')
                ? FluentIcons.add
                : FluentIcons.check_mark,
            size: 14,
            color: displayColor,
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(fontWeight: FontWeight.bold, color: displayColor),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: displayColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count 门',
              style: TextStyle(fontSize: 12, color: displayColor),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建课程行
  Widget _buildCourseRow(
    BuildContext context,
    _CourseInfo course,
    Color color,
    bool isDark, {
    bool compact = false,
  }) {
    final theme = FluentTheme.of(context);
    final displayColor = _getLightVariant(color, isDark);

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: compact ? 6 : 10),
      decoration: BoxDecoration(
        color: theme.resources.subtleFillColorSecondary,
        borderRadius: BorderRadius.circular(4),
        border: compact
            ? null
            : Border.all(color: displayColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          // 课程号（可复制）
          GestureDetector(
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: course.courseCode));
              if (context.mounted) {
                displayInfoBar(
                  context,
                  builder: (context, close) {
                    return InfoBar(
                      title: Text('已复制课程号: ${course.courseCode}'),
                      severity: InfoBarSeverity.success,
                    );
                  },
                );
              }
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: displayColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      course.courseCode,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        color: displayColor,
                        fontSize: compact ? 11 : 13,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(FluentIcons.copy, size: 10, color: displayColor),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 课序号
          Text(
            course.courseSeq,
            style: theme.typography.caption?.copyWith(
              color: theme.inactiveColor,
              fontSize: compact ? 10 : 12,
            ),
          ),
          const SizedBox(width: 12),
          // 课程名
          Expanded(
            child: Text(
              course.courseName,
              style: theme.typography.body?.copyWith(
                fontSize: compact ? 12 : 14,
                color: compact ? theme.inactiveColor : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 学分
          Text(
            '${course.credits}学分',
            style: theme.typography.caption?.copyWith(
              color: theme.inactiveColor,
              fontSize: compact ? 10 : 12,
            ),
          ),
        ],
      ),
    );
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
    BuildContext context,
    SmartCourseSelectionProvider provider,
  ) {
    return PageHeader(
      title: const Text('智能排课', maxLines: 1, overflow: TextOverflow.ellipsis),
      commandBar: CommandBar(
        mainAxisAlignment: MainAxisAlignment.end,
        compactBreakpointWidth: 720,
        primaryItems: _buildCommandBarItems(context, provider),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    SmartCourseSelectionProvider provider,
  ) {
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
      return WinUIEmptyState.noData(title: '暂无数据', description: '正在初始化...');
    }

    return Column(
      children: [
        _buildTermContextBar(context, provider),
        const Divider(),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= _wideCourseSelectionBreakpoint) {
                return _buildWideCourseSelectionLayout(context, provider);
              }
              return _buildCompactCourseSelectionLayout(context, provider);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTermContextBar(
    BuildContext context,
    SmartCourseSelectionProvider provider,
  ) {
    final theme = FluentTheme.of(context);
    final refreshLabel = Text(
      '开课数据 ${_formatRefreshTime(provider.courseDataRefreshTime)}',
      style: theme.typography.caption?.copyWith(color: theme.inactiveColor),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final selector = _buildTermSelector(
            context,
            provider,
            isExpanded: constraints.maxWidth < 560,
          );
          if (constraints.maxWidth < 560) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [selector, const SizedBox(height: 6), refreshLabel],
            );
          }
          return Row(
            children: [
              SizedBox(width: 260, child: selector),
              const SizedBox(width: 12),
              Expanded(child: refreshLabel),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTermSelector(
    BuildContext context,
    SmartCourseSelectionProvider provider, {
    required bool isExpanded,
  }) {
    final terms = provider.termList;
    if (terms == null || terms.isEmpty) return const SizedBox.shrink();

    return ComboBox<String>(
      value: provider.selectedTermCode,
      isExpanded: isExpanded,
      items: terms
          .map(
            (term) => ComboBoxItem<String>(
              value: term.termCode,
              child: Text(
                term.termName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: (value) async {
        if (value == null) return;
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        final userId = authProvider.credentials?.userId ?? '';
        await provider.selectTerm(value, userId);
      },
    );
  }

  Widget _buildWideCourseSelectionLayout(
    BuildContext context,
    SmartCourseSelectionProvider provider,
  ) {
    final borderColor = FluentTheme.of(
      context,
    ).resources.controlStrokeColorDefault;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 300, child: _buildLeftPanel(context, provider)),
        Container(width: 1, color: borderColor),
        Expanded(child: _buildScheduleView(context, provider)),
        Container(width: 1, color: borderColor),
        SizedBox(width: 360, child: _buildSidePanel(context, provider)),
      ],
    );
  }

  Widget _buildCompactCourseSelectionLayout(
    BuildContext context,
    SmartCourseSelectionProvider provider,
  ) {
    return TabView(
      currentIndex: _compactViewIndex,
      onChanged: (index) => setState(() => _compactViewIndex = index),
      closeButtonVisibility: CloseButtonVisibilityMode.never,
      tabWidthBehavior: TabWidthBehavior.equal,
      minTabWidth: 88,
      tabs: [
        Tab(
          icon: const Icon(FluentIcons.education, size: 14),
          text: const Text('培养方案'),
          body: _buildLeftPanel(context, provider),
        ),
        Tab(
          icon: const Icon(FluentIcons.calendar, size: 14),
          text: const Text('课表'),
          body: _buildScheduleView(context, provider),
        ),
        Tab(
          icon: const Icon(FluentIcons.search, size: 14),
          text: const Text('课程'),
          body: _buildAvailableCoursesList(
            context,
            provider,
            onCourseSelected: () {
              setState(() => _compactViewIndex = 3);
            },
          ),
        ),
        Tab(
          icon: const Icon(FluentIcons.info, size: 14),
          text: const Text('详情'),
          body: _buildCourseDetail(context, provider),
        ),
      ],
    );
  }

  /// 构建带进度的加载界面
  Widget _buildLoadingWithProgress(
    BuildContext context,
    SmartCourseSelectionProvider provider,
  ) {
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
                    child: ProgressRing(value: progress * 100, strokeWidth: 6),
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
    BuildContext context,
    SmartCourseSelectionProvider provider,
  ) {
    return Column(
      children: [
        // 课程详情（始终显示，无选中时显示提示）
        Expanded(flex: 3, child: _buildCourseDetail(context, provider)),
        Container(
          height: 1,
          color: FluentTheme.of(context).resources.controlStrokeColorDefault,
        ),
        // 可选课程列表
        Expanded(flex: 2, child: _buildAvailableCoursesList(context, provider)),
      ],
    );
  }

  /// 构建左侧面板（培养方案树）
  Widget _buildLeftPanel(
    BuildContext context,
    SmartCourseSelectionProvider provider,
  ) {
    return _buildPlanTreeView(context, provider);
  }

  /// 构建课程表视图
  Widget _buildScheduleView(
    BuildContext context,
    SmartCourseSelectionProvider provider,
  ) {
    final theme = FluentTheme.of(context);
    final schedule = provider.studentSchedule;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final title = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    FluentIcons.calendar,
                    size: 16,
                    color: theme.accentColor,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      provider.usingClassCurriculum
                          ? '班级课表${provider.classCurriculumName != null ? " · ${provider.classCurriculumName}" : ""}'
                          : '课程表',
                      style: theme.typography.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              );
              final summary = provider.usingClassCurriculum
                  ? '共 ${provider.classCurriculumCourses.length} 条课程安排'
                  : schedule != null
                  ? '已选 ${provider.getEffectiveSelectedCourses().length} 门课程，'
                        '共 ${_calculateEffectiveCredits(provider)} 学分'
                        '${provider.removedCourses.isNotEmpty ? " (退${provider.removedCourses.length}门)" : ""}'
                        '${provider.currentSelectedCourses.isNotEmpty ? " (加${provider.currentSelectedCourses.length}门)" : ""}'
                  : null;
              final summaryText = summary == null
                  ? null
                  : Text(
                      summary,
                      style: theme.typography.caption?.copyWith(
                        color: theme.inactiveColor,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: constraints.maxWidth < 520
                          ? TextAlign.start
                          : TextAlign.end,
                    );

              if (constraints.maxWidth < 520) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    if (summaryText != null) ...[
                      const SizedBox(height: 4),
                      summaryText,
                    ],
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: title),
                  if (summaryText != null) ...[
                    const SizedBox(width: 12),
                    Flexible(child: summaryText),
                  ],
                ],
              );
            },
          ),
        ),
        const Divider(),
        // 课程表网格
        Expanded(
          child: RepaintBoundary(child: _buildScheduleGrid(context, provider)),
        ),
      ],
    );
  }

  double _calculateSimulatedCredits(SmartCourseSelectionProvider provider) {
    double credits = 0;
    for (final key in provider.currentSelectedCourses) {
      final records = provider.getAvailableCourseRecordsByKey(key);
      final course = records.isNotEmpty
          ? records.first
          : CourseScheduleRecord();
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
    BuildContext context,
    SmartCourseSelectionProvider provider,
  ) {
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    const sessions = 10; // 10节课（删除11-12节）
    const double cellHeight = 52.0; // 适中的单元格高度
    const double headerHeight = 32.0;
    const double sessionColumnWidth = 28.0;

    return LayoutBuilder(
      builder: (context, viewportConstraints) {
        final contentWidth =
            viewportConstraints.maxWidth < _minimumScheduleGridWidth
            ? _minimumScheduleGridWidth
            : viewportConstraints.maxWidth;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: contentWidth,
            height: viewportConstraints.maxHeight,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(8),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final availableWidth =
                      constraints.maxWidth - sessionColumnWidth;
                  final cellWidth = availableWidth / 7;

                  return SizedBox(
                    height: headerHeight + cellHeight * sessions,
                    child: Stack(
                      children: [
                        _buildGridBackground(
                          context,
                          provider,
                          weekdays,
                          sessions,
                          cellWidth,
                          cellHeight,
                          headerHeight,
                          sessionColumnWidth,
                        ),
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
            ),
          ),
        );
      },
    );
  }

  /// 构建网格背景
  Widget _buildGridBackground(
    BuildContext context,
    SmartCourseSelectionProvider provider,
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
              ...weekdays.map(
                (d) => Container(
                  width: cellWidth,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border(right: BorderSide(color: borderColor)),
                  ),
                  child: Text(d, style: theme.typography.bodyStrong),
                ),
              ),
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
                      provider.selectCourseAtTimeSlot(null, day, session);
                    },
                    child: Container(
                      width: cellWidth,
                      decoration: BoxDecoration(
                        color:
                            provider.selectedDay == day &&
                                provider.selectedSession == session
                            ? theme.accentColor.withValues(alpha: 0.1)
                            : null,
                        border: Border(right: BorderSide(color: borderColor)),
                      ),
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
    final intervals = <ScheduleCardInterval<Widget>>[];

    void addCard({
      required int weekday,
      required int startSession,
      required int continuingSession,
      required Widget child,
    }) {
      if (weekday < 1 || weekday > 7 || startSession < 1) return;
      final sessionSpan = continuingSession > 0 ? continuingSession : 1;
      intervals.add(
        ScheduleCardInterval(
          item: child,
          weekday: weekday,
          startSession: startSession,
          endSession: startSession + sessionSpan - 1,
        ),
      );
    }

    if (provider.usingClassCurriculum) {
      for (final course in provider.classCurriculumCourses) {
        if (course.skxq == null || course.skjc == null) continue;
        final courseKey = '${course.kch}_${course.kxh}';
        if (provider.removedCourses.contains(courseKey)) continue;
        addCard(
          weekday: course.skxq!,
          startSession: course.skjc!,
          continuingSession: course.cxjc ?? 1,
          child: _buildClassCurriculumCourseCard(context, course, provider),
        );
      }
    } else {
      // 已有课程（排除已退课的）
      if (provider.studentSchedule != null) {
        for (final course in provider.studentSchedule!.courses) {
          final courseKey = '${course.courseCode}_${course.courseSequence}';
          // 跳过已退课的课程
          if (provider.removedCourses.contains(courseKey)) continue;

          for (final tp in course.timeAndPlaceList) {
            addCard(
              weekday: tp.classDay,
              startSession: tp.classSessions,
              continuingSession: tp.continuingSession,
              child: _buildExistingCourseCard(context, course, tp, provider),
            );
          }
        }
      }
    }

    // 模拟选课（新增的课程）
    for (final key in provider.currentSelectedCourses) {
      for (final course in provider.getAvailableCourseRecordsByKey(key)) {
        if (course.skxq == null || course.skjc == null) continue;

        addCard(
          weekday: course.skxq!,
          startSession: course.skjc!,
          continuingSession: course.cxjc ?? 1,
          child: _buildSimulatedCourseCard(context, course, provider),
        );
      }
    }

    return layoutScheduleCardIntervals(intervals).map((placement) {
      final interval = placement.interval;
      final laneWidth = cellWidth / placement.laneCount;
      final cardWidth = (laneWidth - 4).clamp(1.0, double.infinity).toDouble();
      final sessionSpan = interval.endSession - interval.startSession + 1;
      final cardHeight = (sessionSpan * cellHeight - 4)
          .clamp(1.0, double.infinity)
          .toDouble();

      return Positioned(
        left:
            sessionColumnWidth +
            (interval.weekday - 1) * cellWidth +
            placement.lane * laneWidth +
            2,
        top: headerHeight + (interval.startSession - 1) * cellHeight + 2,
        width: cardWidth,
        height: cardHeight,
        child: interval.item,
      );
    }).toList();
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
        // 优先从 availableCourses 中查找完整的课程记录（包含 bkskyl 等字段）
        final courseKey = '${course.courseCode}_${course.courseSequence}';
        final records = provider.getAvailableCourseRecordsByKey(courseKey);
        final matched = records.isEmpty
            ? CourseScheduleRecord()
            : records.first;
        // 必须用学生课表的 courseSequence 作为 kxh，保证 courseKey 与 baseScheduleSnapshot 一致
        final fullRecord = matched.kch != null
            ? CourseScheduleRecord(
                id: matched.id,
                zxjxjhh: matched.zxjxjhh,
                kch: matched.kch,
                kxh: course.courseSequence,
                kcm: matched.kcm ?? course.courseName,
                xf: matched.xf ?? course.unit.toInt(),
                xs: matched.xs,
                kkxsh: matched.kkxsh,
                kkxsjc: matched.kkxsjc,
                kslxdm: matched.kslxdm,
                kslxmc: matched.kslxmc,
                skjs: matched.skjs ?? course.attendClassTeacher,
                bkskrl: matched.bkskrl,
                bkskyl: matched.bkskyl,
                xkmsdm: matched.xkmsdm,
                xkmssm: matched.xkmssm,
                xkkzdm: matched.xkkzdm,
                xkkzsm: matched.xkkzsm,
                xkkzh: matched.xkkzh,
                xkxzsm: matched.xkxzsm,
                kkxqh: matched.kkxqh,
                kkxqm: matched.kkxqm,
                xqh: matched.xqh,
                jxlh: matched.jxlh,
                jash: matched.jash,
                skzc: matched.skzc,
                skxq: tp.classDay,
                skjc: tp.classSessions,
                cxjc: tp.continuingSession,
                zcsm: tp.weekDescription,
                kclbdm: matched.kclbdm,
                kclbmc: matched.kclbmc,
                xkbz: matched.xkbz,
                xqm: tp.campusName,
                jxlm: tp.teachingBuildingName,
                jasm: tp.classroomName,
                mxbj: matched.mxbj,
                xss: matched.xss,
              )
            : CourseScheduleRecord(
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
              );
        provider.selectCourseAtTimeSlot(
          fullRecord,
          tp.classDay,
          tp.classSessions,
        );
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

  /// 构建班级课表课程卡片
  Widget _buildClassCurriculumCourseCard(
    BuildContext context,
    CourseScheduleRecord course,
    SmartCourseSelectionProvider provider,
  ) {
    final theme = FluentTheme.of(context);

    return GestureDetector(
      onTap: () {
        if (course.skxq != null && course.skjc != null) {
          provider.selectCourseAtTimeSlot(course, course.skxq!, course.skjc!);
        } else {
          provider.selectCourse(course);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: theme.accentColor.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: theme.accentColor.withValues(alpha: 0.45)),
        ),
        padding: const EdgeInsets.all(3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              course.kcm ?? '',
              style: theme.typography.caption?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.accentColor,
                fontSize: 10,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const Spacer(),
            Text(
              course.jasm ?? course.skjs ?? '',
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

  /// 构建模拟选课卡片
  Widget _buildSimulatedCourseCard(
    BuildContext context,
    CourseScheduleRecord course,
    SmartCourseSelectionProvider provider,
  ) {
    final theme = FluentTheme.of(context);

    return GestureDetector(
      onTap: () {
        if (course.skxq != null && course.skjc != null) {
          provider.selectCourseAtTimeSlot(course, course.skxq!, course.skjc!);
        } else {
          provider.selectCourse(course);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
        ),
        padding: const EdgeInsets.all(3),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final courseName = Text(
              course.kcm ?? '',
              style: theme.typography.caption?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.green,
                fontSize: 10,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (constraints.maxWidth >= 44)
                  Row(
                    children: [
                      Expanded(child: courseName),
                      Icon(
                        FluentIcons.add_event,
                        size: 10,
                        color: Colors.green,
                      ),
                    ],
                  )
                else
                  courseName,
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
            );
          },
        ),
      ),
    );
  }

  /// 构建课程详情
  Widget _buildCourseDetail(
    BuildContext context,
    SmartCourseSelectionProvider provider,
  ) {
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
              style: theme.typography.body?.copyWith(
                color: theme.inactiveColor,
              ),
            ),
          ],
        ),
      );
    }

    final courseKey = '${course.kch}_${course.kxh}';
    final allRecords = provider.getAvailableCourseRecordsByKey(courseKey);
    final isNewlySelected = provider.currentSelectedCourses.contains(courseKey);
    final isFromOriginalSchedule = provider.isCourseFromOriginalSchedule(
      courseKey,
    );
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.teal.light : Colors.teal)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        FluentIcons.check_mark,
                        size: 12,
                        color: isDark ? Colors.teal.light : Colors.teal,
                      ),
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
          _buildDetailRow(
            context,
            '教室',
            '${course.jxlm ?? ''} ${course.jasm ?? ''}',
          ),
          // 时间（显示所有上课时间）
          ...(() {
            final times = allRecords
                .map((r) => r.scheduleDescription)
                .where((d) => d.isNotEmpty)
                .toList();
            if (times.isEmpty) {
              return [
                _buildDetailRow(context, '时间', course.scheduleDescription),
              ];
            }
            return times.asMap().entries.map((entry) {
              return _buildDetailRow(
                context,
                entry.key == 0 ? '时间' : '  ',
                '${entry.key == 0 ? "" : "· "}${entry.value}',
              );
            });
          })(),
          _buildDetailRow(
            context,
            '容量',
            '${course.bkskrl ?? 0} / 余量: ${_getActualCapacity(course)}',
          ),
          // 选课限制说明
          if (course.xkxzsm != null && course.xkxzsm!.isNotEmpty)
            _buildDetailRow(context, '选课限制', course.xkxzsm!),
          // 选课控制说明
          if (course.xkkzsm != null && course.xkkzsm!.isNotEmpty)
            _buildDetailRow(context, '选课控制', course.xkkzsm!),
          // 面向班级
          if (course.mxbj != null && course.mxbj!.isNotEmpty)
            _buildDetailRow(context, '面向班级', course.mxbj!),
          const SizedBox(height: 8),
          // 选课备注（单独显示，可能较长）
          if (course.xkbz != null && course.xkbz!.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (isDark ? Colors.blue.light : Colors.blue).withValues(
                  alpha: 0.1,
                ),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: (isDark ? Colors.blue.light : Colors.blue).withValues(
                    alpha: 0.3,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        FluentIcons.info,
                        size: 12,
                        color: isDark ? Colors.blue.light : Colors.blue,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '选课备注',
                        style: theme.typography.caption?.copyWith(
                          color: isDark ? Colors.blue.light : Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    course.xkbz!,
                    style: theme.typography.caption?.copyWith(
                      color: isDark ? Colors.blue.light : Colors.blue,
                    ),
                  ),
                ],
              ),
            ),
          // 冲突提示
          if (hasConflict &&
              !isNewlySelected &&
              !isFromOriginalSchedule &&
              !isPassed)
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
                  isPassed: isPassed,
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
          Expanded(child: Text(value, style: theme.typography.caption)),
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
    required bool isPassed,
  }) {
    // 已修课程不在当前课表中时，不提供任何操作
    if (isPassed && !isFromOriginalSchedule && !isNewlySelected && !isRemoved) {
      return const SizedBox.shrink();
    }

    // 情况1：新增的课程 -> 显示"模拟退课"
    if (isNewlySelected) {
      return Button(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.all(
            Colors.red.withValues(alpha: 0.1),
          ),
        ),
        onPressed: () async {
          final authProvider = Provider.of<AuthProvider>(
            context,
            listen: false,
          );
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
          backgroundColor: WidgetStateProperty.all(
            Colors.orange.withValues(alpha: 0.1),
          ),
        ),
        onPressed: () async {
          final authProvider = Provider.of<AuthProvider>(
            context,
            listen: false,
          );
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
                final authProvider = Provider.of<AuthProvider>(
                  context,
                  listen: false,
                );
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
              final authProvider = Provider.of<AuthProvider>(
                context,
                listen: false,
              );
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

  /// 构建课程检索与当前时间段的可选课程列表。
  Widget _buildAvailableCoursesList(
    BuildContext context,
    SmartCourseSelectionProvider provider, {
    VoidCallback? onCourseSelected,
  }) {
    final theme = FluentTheme.of(context);
    final selectedDay = provider.selectedDay;
    final selectedSession = provider.selectedSession;
    final hasTimeSlot = selectedDay != null && selectedSession != null;
    final courses = provider.visibleCourseResults;
    const weekdays = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final title = hasTimeSlot
        ? '${weekdays[selectedDay]} 第$selectedSession节'
        : provider.hasCourseSearchQuery
        ? '全学期课程'
        : '可选课程';
    final showResultCount = hasTimeSlot || provider.hasCourseSearchQuery;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
          child: Row(
            children: [
              Icon(FluentIcons.library, size: 16, color: theme.accentColor),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: theme.typography.subtitle)),
              if (showResultCount)
                Text(
                  '${courses.length} 门',
                  style: theme.typography.caption?.copyWith(
                    color: theme.inactiveColor,
                  ),
                ),
              const SizedBox(width: 4),
              Tooltip(
                message: _showCourseFilters ? '收起筛选' : '展开筛选',
                child: IconButton(
                  icon: Icon(
                    FluentIcons.filter,
                    size: 14,
                    color: _showCourseFilters
                        ? theme.accentColor
                        : theme.inactiveColor,
                  ),
                  onPressed: () {
                    setState(() => _showCourseFilters = !_showCourseFilters);
                  },
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextBox(
            controller: _courseSearchController,
            placeholder: '搜索课程、教师或课程号',
            prefix: const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(FluentIcons.search, size: 14),
            ),
            suffix: provider.hasCourseSearchQuery
                ? Tooltip(
                    message: '清除搜索',
                    child: IconButton(
                      icon: const Icon(FluentIcons.clear, size: 12),
                      onPressed: () {
                        _courseSearchController.clear();
                        provider.clearCourseSearch();
                      },
                    ),
                  )
                : null,
            onChanged: provider.setCourseSearchQuery,
          ),
        ),
        if (hasTimeSlot)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Align(
              alignment: Alignment.centerRight,
              child: Button(
                onPressed: provider.clearSelectedTimeSlot,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.calendar, size: 12),
                    SizedBox(width: 6),
                    Text('取消时段'),
                  ],
                ),
              ),
            ),
          ),
        if (_showCourseFilters)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _buildFilterControls(context, provider),
          )
        else
          _buildFilterSummary(context, provider),
        const SizedBox(height: 6),
        const Divider(),
        Expanded(
          child: !hasTimeSlot && !provider.hasCourseSearchQuery
              ? _buildCourseResultEmptyState(
                  context,
                  FluentIcons.calendar_week,
                  '未选择时间段',
                )
              : courses.isEmpty
              ? _buildCourseResultEmptyState(
                  context,
                  FluentIcons.search_issue,
                  provider.hasCourseSearchQuery ? '未找到相关课程' : '暂无可选课程',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                  itemCount: courses.length,
                  itemBuilder: (context, index) {
                    return _buildCourseResultTile(
                      context,
                      provider,
                      courses[index],
                      onCourseSelected: onCourseSelected,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCourseResultEmptyState(
    BuildContext context,
    IconData icon,
    String message,
  ) {
    final theme = FluentTheme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 32, color: theme.inactiveColor),
          const SizedBox(height: 10),
          Text(
            message,
            style: theme.typography.body?.copyWith(color: theme.inactiveColor),
          ),
        ],
      ),
    );
  }

  Widget _buildCourseResultTile(
    BuildContext context,
    SmartCourseSelectionProvider provider,
    CourseScheduleRecord course, {
    VoidCallback? onCourseSelected,
  }) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final courseKey = '${course.kch}_${course.kxh}';
    final records = provider.getAvailableCourseRecordsByKey(courseKey);
    final scheduleText = records
        .map((record) => record.scheduleDescription)
        .where((description) => description.isNotEmpty)
        .toSet()
        .join('；');
    final isInSchedule = provider.isCourseInSchedule(courseKey);
    final isPassed = provider.isCoursePassed(course.kch);
    final hasConflict = !isInSchedule && !isPassed
        ? provider.checkConflict(course)
        : false;
    final score = provider.getCourseScore(course.kch);
    final statusColor = isPassed
        ? (isDark ? Colors.teal.light : Colors.teal)
        : isInSchedule
        ? Colors.green
        : hasConflict
        ? Colors.orange
        : theme.inactiveColor;
    final metadata = [
      course.kch,
      if ((course.kxh ?? '').isNotEmpty) '课序 ${course.kxh}',
      course.skjs,
      course.xqm,
    ].whereType<String>().where((value) => value.isNotEmpty).join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ListTile.selectable(
        selected:
            provider.selectedCourse?.kch == course.kch &&
            provider.selectedCourse?.kxh == course.kxh,
        leading: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                course.kcm ?? course.kch ?? '未知课程',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: isPassed
                    ? theme.typography.body?.copyWith(
                        color: theme.inactiveColor,
                      )
                    : theme.typography.bodyStrong,
              ),
            ),
            if (isPassed)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text(
                  '已修${score != null ? " $score" : ""}',
                  style: theme.typography.caption?.copyWith(color: statusColor),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (metadata.isNotEmpty)
              Text(
                metadata,
                style: theme.typography.caption?.copyWith(
                  color: isPassed ? theme.inactiveColor : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            if (scheduleText.isNotEmpty)
              Text(
                scheduleText,
                style: theme.typography.caption?.copyWith(
                  color: theme.inactiveColor,
                  fontSize: 10,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        trailing: SizedBox(
          width: 48,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${course.xf ?? 0}学分', style: theme.typography.caption),
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
        ),
        onPressed: () {
          provider.selectCourse(course);
          onCourseSelected?.call();
        },
      ),
    );
  }

  Widget _buildFilterSummary(
    BuildContext context,
    SmartCourseSelectionProvider provider,
  ) {
    final theme = FluentTheme.of(context);
    final filters = <String>[
      if (provider.filterCampus != null) provider.filterCampus!,
      if (provider.filterPlanOnly) '计划内',
      if (provider.filterOutOfPlanOnly) '计划外',
      if (provider.filterHidePassed) '隐藏已修',
      if (provider.filterHideCompletedCategory) '隐藏已完成分类',
    ];
    if (filters.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Row(
        children: [
          Icon(FluentIcons.filter_solid, size: 10, color: theme.inactiveColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              filters.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.typography.caption?.copyWith(
                color: theme.inactiveColor,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建筛选控件
  Widget _buildFilterControls(
    BuildContext context,
    SmartCourseSelectionProvider provider,
  ) {
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
                    ...campuses.map(
                      (c) => ComboBoxItem<String?>(value: c, child: Text(c)),
                    ),
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
              // 只看培养方案内
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ToggleSwitch(
                    checked: provider.filterPlanOnly,
                    onChanged: (value) {
                      provider.setFilter(planOnly: value);
                    },
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '计划内',
                    style: theme.typography.caption?.copyWith(
                      color: provider.filterPlanOnly
                          ? (isDark ? Colors.teal.light : Colors.teal)
                          : theme.inactiveColor,
                    ),
                  ),
                ],
              ),
              // 只看不在培养方案内
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ToggleSwitch(
                    checked: provider.filterOutOfPlanOnly,
                    onChanged: (value) {
                      provider.setFilter(outOfPlanOnly: value);
                    },
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '计划外',
                    style: theme.typography.caption?.copyWith(
                      color: provider.filterOutOfPlanOnly
                          ? (isDark ? Colors.teal.light : Colors.teal)
                          : theme.inactiveColor,
                    ),
                  ),
                ],
              ),
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
    BuildContext context,
    SmartCourseSelectionProvider provider,
  ) {
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
          child: planInfo == null || planInfo.categories.isEmpty
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
                        .map(
                          (cat) =>
                              _buildPlanCategoryNode(context, provider, cat),
                        )
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
    PlanCategory category, {
    int depth = 0,
  }) {
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
            Icon(
              FluentIcons.check_mark,
              size: 12,
              color: isDark ? Colors.green.light : Colors.green,
            ),
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
                color: (isDark ? Colors.green.light : Colors.green).withValues(
                  alpha: 0.15,
                ),
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
      initiallyExpanded: depth < 2 || availableCount > 0,
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
                color: (isDark ? Colors.green.light : Colors.green).withValues(
                  alpha: 0.15,
                ),
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
          ...category.subcategories.map<Widget>(
            (sub) => Padding(
              padding: const EdgeInsets.only(left: 12),
              child: _buildPlanCategoryNode(
                context,
                provider,
                sub,
                depth: depth + 1,
              ),
            ),
          ),
          // 课程列表（优先显示有开课的，然后显示未开课的，最后显示已修的）
          ...category.courses
              .where(
                (course) =>
                    !course.isPassed &&
                    provider.isCourseAvailableInTerm(course.courseCode),
              )
              .map<Widget>(
                (course) => _buildPlanCourseNode(
                  context,
                  provider,
                  course,
                  status: 'available',
                ),
              ),
          // 未开课的课程（灰色显示）
          ...category.courses
              .where(
                (course) =>
                    !course.isPassed &&
                    !provider.isCourseAvailableInTerm(course.courseCode),
              )
              .map<Widget>(
                (course) => _buildPlanCourseNode(
                  context,
                  provider,
                  course,
                  status: 'unavailable',
                ),
              ),
          // 已修的课程（绿色显示）
          ...category.courses
              .where((course) => course.isPassed)
              .map<Widget>(
                (course) => _buildPlanCourseNode(
                  context,
                  provider,
                  course,
                  status: 'passed',
                ),
              ),
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
    final scheduleRecords = provider.getCourseScheduleRecords(
      course.courseCode,
    );
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
        final creditText = course.credits != null
            ? '${course.credits}学分'
            : null;
        if (score != null && creditText != null) {
          trailingText = '已修 $score · $creditText';
        } else if (score != null) {
          trailingText = '已修 $score';
        } else if (creditText != null) {
          trailingText = '已修 · $creditText';
        } else {
          trailingText = '已修';
        }
        bgColor = (isDark ? Colors.teal.light : Colors.teal).withValues(
          alpha: 0.08,
        );
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
                  course.courseName.isNotEmpty
                      ? course.courseName
                      : course.courseCode,
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
        headerBackgroundColor: WidgetStateColor.resolveWith(
          (_) => bgColor ?? Colors.transparent,
        ),
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
                course.courseName.isNotEmpty
                    ? course.courseName
                    : course.courseCode,
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
          children: () {
            // 按 kch_kxh 分组，合并同一课序号的多个时间段
            final grouped = <String, List<CourseScheduleRecord>>{};
            for (final r in scheduleRecords) {
              final key = '${r.kch}_${r.kxh}';
              grouped.putIfAbsent(key, () => []).add(r);
            }
            return grouped.values.map((records) {
              records.sort((a, b) {
                final aDay = a.skxq ?? 7;
                final bDay = b.skxq ?? 7;
                if (aDay != bDay) return aDay.compareTo(bDay);
                return (a.skjc ?? 0).compareTo(b.skjc ?? 0);
              });
              final first = records.first;
              final courseKey = '${first.kch}_${first.kxh}';
              final isSelected = provider.currentSelectedCourses.contains(
                courseKey,
              );
              final hasConflict = records.any((r) => provider.checkConflict(r));

              return GestureDetector(
                onTap: () => provider.selectCourse(first),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
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
                              : (hasConflict
                                    ? Colors.orange
                                    : theme.accentColor),
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
                                  '${first.kxh ?? ""}班',
                                  style: theme.typography.caption?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    first.skjs ?? '',
                                    style: theme.typography.caption?.copyWith(
                                      color: theme.inactiveColor,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            // 显示所有上课时间
                            ...records.map((r) {
                              final desc = r.scheduleDescription;
                              return desc.isNotEmpty
                                  ? Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        '${r.xqm ?? ""} · $desc',
                                        style: theme.typography.caption
                                            ?.copyWith(
                                              fontSize: 10,
                                              color: theme.inactiveColor,
                                              height: 1.3,
                                            ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    )
                                  : const SizedBox.shrink();
                            }),
                          ],
                        ),
                      ),
                      // 余量
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (isSelected)
                            Icon(
                              FluentIcons.check_mark,
                              size: 12,
                              color: Colors.green,
                            )
                          else if (hasConflict)
                            Icon(
                              FluentIcons.warning,
                              size: 12,
                              color: Colors.orange,
                            ),
                          Text(
                            '余${_getActualCapacity(first)}',
                            style: theme.typography.caption?.copyWith(
                              fontSize: 9,
                              color: _getActualCapacityInt(first) > 0
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
            }).toList();
          }(),
        ),
      ),
    );
  }

  /// 构建培养方案选择视图（多培养方案用户）
  Widget _buildPlanSelectionView(
    BuildContext context,
    SmartCourseSelectionProvider provider,
  ) {
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
                      Expanded(child: Text(hint, style: theme.typography.body)),
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
                        Text('选择培养方案', style: theme.typography.subtitle),
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
              ...options.map(
                (option) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildPlanOptionCard(context, option, provider),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建培养方案选项卡片
  Widget _buildPlanOptionCard(
    BuildContext context,
    PlanOption option,
    SmartCourseSelectionProvider provider,
  ) {
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
                  Text(option.planName, style: theme.typography.bodyStrong),
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
