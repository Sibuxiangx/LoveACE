import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../models/jwc/teacher_evaluation.dart';
import '../../providers/teacher_evaluation_provider.dart';
import '../widgets/winui_card.dart';
import '../widgets/winui_empty_state.dart';
import '../widgets/winui_loading.dart';
import '../mixins/user_scope_data_loader.dart';

class WinUITeacherEvaluationPage extends StatefulWidget {
  const WinUITeacherEvaluationPage({super.key});

  @override
  State<WinUITeacherEvaluationPage> createState() => _WinUITeacherEvaluationPageState();
}

class _WinUITeacherEvaluationPageState
    extends State<WinUITeacherEvaluationPage>
    with UserScopeDataLoader<WinUITeacherEvaluationPage> {
  @override
  bool get isUserScopeReady =>
      Provider.of<TeacherEvaluationProvider?>(context, listen: false) != null;

  @override
  void loadUserScopeData() => _load();

  Future<void> _load() async {
    final provider = Provider.of<TeacherEvaluationProvider?>(context, listen: false);
    await provider?.load();
  }

  Future<void> _confirmStart(TeacherEvaluationProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('开始批量自动评教'),
        content: const Text(
          '系统将只处理待评课程：每 6 秒启动一门，生成表单后等待 140 秒再提交。请保持应用前台；已提交的评价无法撤回。',
        ),
        actions: [
          Button(
            child: const Text('取消'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          FilledButton(
            child: const Text('开始'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed == true) await provider.startBatch();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TeacherEvaluationProvider?>(
      builder: (context, provider, _) {
        if (provider == null) {
          return const ScaffoldPage(
            header: PageHeader(title: Text('自动评教')),
            content: WinUILoading(message: '正在初始化...'),
          );
        }

        return ScaffoldPage(
          header: PageHeader(
            title: const Text('自动评教'),
            commandBar: CommandBar(
              mainAxisAlignment: MainAxisAlignment.end,
              primaryItems: [
                CommandBarButton(
                  icon: const Icon(FluentIcons.refresh),
                  label: const Text('刷新'),
                  onPressed: provider.isRunning ? null : _load,
                ),
              ],
            ),
          ),
          content: _buildContent(provider),
        );
      },
    );
  }

  Widget _buildContent(TeacherEvaluationProvider provider) {
    if (provider.state == TeacherEvaluationState.loading) {
      return const WinUILoading(message: '正在加载评教课程...');
    }
    if (provider.state == TeacherEvaluationState.closed) {
      return WinUIEmptyState.noData(
        title: '评价暂未开启',
        description: provider.closedMessage,
        actionText: '刷新',
        onAction: _load,
      );
    }
    if (provider.state == TeacherEvaluationState.error) {
      return WinUIEmptyState.needRefresh(
        title: '加载失败',
        description: provider.errorMessage ?? '请刷新重试',
        onAction: _load,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 900;
        final controlPanel = SizedBox(
          width: narrow ? double.infinity : 340,
          child: _buildControlPanel(provider),
        );
        final detailPanel = Expanded(child: _buildDetailPanel(provider));

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: narrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    controlPanel,
                    const SizedBox(height: 16),
                    _buildDetailPanel(provider),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    controlPanel,
                    const SizedBox(width: 16),
                    detailPanel,
                  ],
                ),
        );
      },
    );
  }

  Widget _buildControlPanel(TeacherEvaluationProvider provider) {
    final theme = FluentTheme.of(context);
    final pending = provider.pendingCourses.length;
    final total = provider.courses.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WinUICard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(FluentIcons.review_request_solid, size: 28, color: theme.accentColor),
              const SizedBox(height: 14),
              Text('批量自动评教', style: theme.typography.subtitle?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(
                '按标准间隔提交待评课程，过程可随时停止。',
                style: theme.typography.body?.copyWith(color: theme.inactiveColor),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(child: _metric('待评', pending.toString(), theme.accentColor)),
                  const SizedBox(width: 10),
                  Expanded(child: _metric('已评', provider.evaluatedCount.toString(), Colors.green)),
                  const SizedBox(width: 10),
                  Expanded(child: _metric('全部', total.toString(), theme.inactiveColor)),
                ],
              ),
              const SizedBox(height: 18),
              _buildSafetyNotice(),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: !provider.isRunning && pending > 0 ? () => _confirmStart(provider) : null,
                      child: const Text('开始'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Button(
                    onPressed: provider.isRunning ? provider.stop : null,
                    child: const Text('停止'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildLogs(provider.logs),
      ],
    );
  }

  Widget _metric(String label, String value, Color color) {
    final theme = FluentTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: theme.typography.subtitle?.copyWith(fontWeight: FontWeight.w600)),
          Text(label, style: theme.typography.caption?.copyWith(color: theme.inactiveColor)),
        ],
      ),
    );
  }

  Widget _buildSafetyNotice() {
    return InfoBar(
      title: const Text('提交前会等待 140 秒'),
      content: const Text('停止只会取消未提交任务。已提交评价无法撤回。'),
      severity: InfoBarSeverity.warning,
      isLong: true,
    );
  }

  Widget _buildLogs(List<String> logs) {
    final theme = FluentTheme.of(context);
    return WinUICard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(FluentIcons.history, size: 15),
              const SizedBox(width: 8),
              Text('最近日志', style: theme.typography.bodyStrong),
            ],
          ),
          const SizedBox(height: 10),
          if (logs.isEmpty)
            Text('暂无操作记录', style: theme.typography.caption?.copyWith(color: theme.inactiveColor))
          else
            ...logs.reversed.take(8).map(
                  (log) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(log, style: theme.typography.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildDetailPanel(TeacherEvaluationProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (provider.tasks.isNotEmpty) ...[
          _section('任务队列', '显示本次批量评教的实时状态', _buildTaskList(provider.tasks)),
          const SizedBox(height: 16),
        ],
        _section('课程列表', '来自教务系统的评教课程', _buildCourseTable(provider.courses)),
      ],
    );
  }

  Widget _section(String title, String subtitle, Widget child) {
    final theme = FluentTheme.of(context);
    return WinUICard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.typography.subtitle?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle, style: theme.typography.caption?.copyWith(color: theme.inactiveColor)),
              ],
            ),
          ),
          const Divider(size: 1),
          child,
        ],
      ),
    );
  }

  Widget _buildTaskList(List<TeacherEvaluationTaskState> tasks) {
    return Column(children: tasks.map(_taskRow).toList());
  }

  Widget _taskRow(TeacherEvaluationTaskState task) {
    final color = _statusColor(task.status);
    final countdown = task.countdownSeconds > 0 ? ' · ${task.countdownSeconds}s' : '';
    return _desktopRow(
      leading: _statusGlyph(_statusIcon(task.status), color),
      title: task.course.name.ifEmpty('未命名课程'),
      subtitle: task.course.teacher,
      trailing: _statusPill('${task.message}$countdown', color),
    );
  }

  Widget _buildCourseTable(List<TeacherEvaluationCourse> courses) {
    if (courses.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(18),
        child: WinUIEmptyState.noData(
          title: '暂无评教课程',
          description: '如果评教已开启，可以稍后刷新重试。',
        ),
      );
    }
    return Column(children: courses.map(_courseRow).toList());
  }

  Widget _courseRow(TeacherEvaluationCourse course) {
    final color = course.isEvaluated ? Colors.green : Colors.orange;
    return _desktopRow(
      leading: _statusGlyph(course.isEvaluated ? FluentIcons.completed : FluentIcons.edit, color),
      title: course.name.ifEmpty('未命名课程'),
      subtitle: course.teacher,
      trailing: _statusPill(course.isEvaluated ? '已评' : '待评', color),
    );
  }

  Widget _desktopRow({
    required Widget leading,
    required String title,
    required String subtitle,
    required Widget trailing,
  }) {
    final theme = FluentTheme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.resources.controlStrokeColorDefault.withValues(alpha: 0.55))),
      ),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (subtitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle,
                      style: theme.typography.caption?.copyWith(color: theme.inactiveColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }

  Widget _statusGlyph(IconData icon, Color color) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, color: color, size: 15),
    );
  }

  Widget _statusPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 12)),
    );
  }

  Color _statusColor(TeacherEvaluationTaskStatus status) => switch (status) {
        TeacherEvaluationTaskStatus.success => Colors.green,
        TeacherEvaluationTaskStatus.failed => Colors.red,
        TeacherEvaluationTaskStatus.cancelled => Colors.grey,
        TeacherEvaluationTaskStatus.waiting => Colors.orange,
        _ => FluentTheme.of(context).accentColor,
      };

  IconData _statusIcon(TeacherEvaluationTaskStatus status) => switch (status) {
        TeacherEvaluationTaskStatus.success => FluentIcons.completed,
        TeacherEvaluationTaskStatus.failed => FluentIcons.error,
        TeacherEvaluationTaskStatus.cancelled => FluentIcons.blocked,
        TeacherEvaluationTaskStatus.waiting => FluentIcons.clock,
        TeacherEvaluationTaskStatus.submitting => FluentIcons.upload,
        TeacherEvaluationTaskStatus.verifying => FluentIcons.sync,
        _ => FluentIcons.processing,
      };
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
