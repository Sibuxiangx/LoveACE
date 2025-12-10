import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import '../../models/competition/award_project.dart';
import '../../models/competition/competition_full_response.dart';
import '../../providers/competition_provider.dart';
import '../widgets/winui_card.dart';
import '../widgets/winui_loading.dart';
import '../widgets/winui_empty_state.dart';
import '../widgets/winui_dialogs.dart';

/// WinUI 风格的学科竞赛页面
///
/// 桌面端布局：左侧学分汇总 + 右侧获奖列表/详情
/// 复用 CompetitionProvider 进行数据管理
/// _Requirements: 10.1, 10.2, 10.3, 10.4_
class WinUICompetitionPage extends StatefulWidget {
  const WinUICompetitionPage({super.key});

  @override
  State<WinUICompetitionPage> createState() => _WinUICompetitionPageState();
}

class _WinUICompetitionPageState extends State<WinUICompetitionPage> {
  /// 当前选中的获奖项目
  AwardProject? _selectedAward;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    final provider = Provider.of<CompetitionProvider>(context, listen: false);
    await provider.loadData(forceRefresh: forceRefresh);

    if (mounted && provider.state == CompetitionState.error) {
      _showErrorDialog(provider.errorMessage ?? '加载失败', provider.isRetryable);
    }
  }

  Future<void> _refreshData() async {
    setState(() => _selectedAward = null);
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

  @override
  Widget build(BuildContext context) {
    return Consumer<CompetitionProvider>(
      builder: (context, provider, child) {
        return ScaffoldPage(
          header: PageHeader(
            title: const Text('学科竞赛'),
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

  Widget _buildContent(BuildContext context, CompetitionProvider provider) {
    if (provider.state == CompetitionState.loading) {
      return const WinUILoading(message: '正在加载竞赛信息');
    }

    if (provider.state == CompetitionState.loaded) {
      final info = provider.competitionInfo;
      if (info == null || info.awards.isEmpty) {
        return WinUIEmptyState.noData(
          title: '暂无获奖项目',
          description: '您还没有申报任何获奖项目',
          actionText: '刷新',
          onAction: _refreshData,
        );
      }
      return _buildMainLayout(context, info);
    }

    if (provider.state == CompetitionState.error) {
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

  /// 桌面端主布局：左侧汇总 + 右侧列表/详情
  Widget _buildMainLayout(BuildContext context, CompetitionFullResponse info) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左侧：学分汇总
        SizedBox(
          width: 320,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _buildCreditsSummaryCard(context, info),
          ),
        ),
        Container(
          width: 1,
          color: FluentTheme.of(context).resources.controlStrokeColorDefault,
        ),
        // 右侧：获奖列表或详情
        Expanded(
          child: _selectedAward != null
              ? _buildAwardDetail(context, _selectedAward!)
              : _buildAwardsList(context, info),
        ),
      ],
    );
  }


  /// 构建学分汇总卡片
  Widget _buildCreditsSummaryCard(BuildContext context, CompetitionFullResponse info) {
    final theme = FluentTheme.of(context);
    final summary = info.creditsSummary;
    final isDark = theme.brightness == Brightness.dark;

    return WinUICard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(FluentIcons.trophy, size: 20, color: theme.accentColor),
              const SizedBox(width: 8),
              Text('学分汇总', style: theme.typography.subtitle),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '学生ID: ${info.studentId}',
            style: theme.typography.caption?.copyWith(color: theme.inactiveColor),
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),
          // 总学分
          Center(
            child: Column(
              children: [
                Text('总学分', style: theme.typography.caption?.copyWith(color: theme.inactiveColor)),
                const SizedBox(height: 4),
                Text(
                  summary?.totalCredits.toStringAsFixed(2) ?? '0.00',
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
          // 各类学分统计
          if (summary != null) ...[
            _buildCreditStatItem(context, '学科竞赛', summary.disciplineCompetitionCredits ?? 0, FluentIcons.trophy2, isDark ? Colors.red.light : Colors.red),
            const SizedBox(height: 8),
            _buildCreditStatItem(context, '科研项目', summary.scientificResearchCredits ?? 0, FluentIcons.test_beaker, isDark ? Colors.blue.light : Colors.blue),
            const SizedBox(height: 8),
            _buildCreditStatItem(context, '可转竞赛类', summary.transferableCompetitionCredits ?? 0, FluentIcons.switch_widget, isDark ? Colors.orange.light : Colors.orange),
            const SizedBox(height: 8),
            _buildCreditStatItem(context, '创新创业实践', summary.innovationPracticeCredits ?? 0, FluentIcons.lightbulb, isDark ? Colors.green.light : Colors.green),
            const SizedBox(height: 8),
            _buildCreditStatItem(context, '能力资格认证', summary.abilityCertificationCredits ?? 0, FluentIcons.certificate, isDark ? Colors.purple.light : Colors.purple),
            const SizedBox(height: 8),
            _buildCreditStatItem(context, '其他项目', summary.otherProjectCredits ?? 0, FluentIcons.more, theme.inactiveColor),
          ],
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),
          // 获奖数量统计
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildCountStat(context, '获奖总数', '${info.awards.length}', theme.accentColor),
              _buildCountStat(context, '国家级', '${info.awards.where((a) => a.level.contains('国家级')).length}', isDark ? Colors.red.light : Colors.red),
              _buildCountStat(context, '省部级', '${info.awards.where((a) => a.level.contains('省') || a.level.contains('部')).length}', isDark ? Colors.orange.light : Colors.orange),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCreditStatItem(BuildContext context, String label, double value, IconData icon, Color color) {
    final theme = FluentTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: theme.typography.body),
          ),
          Text(
            value.toStringAsFixed(2),
            style: theme.typography.bodyStrong?.copyWith(color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildCountStat(BuildContext context, String label, String value, Color color) {
    final theme = FluentTheme.of(context);
    return Column(
      children: [
        Text(value, style: theme.typography.title?.copyWith(fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 2),
        Text(label, style: theme.typography.caption?.copyWith(color: theme.inactiveColor)),
      ],
    );
  }

  /// 构建获奖列表
  Widget _buildAwardsList(BuildContext context, CompetitionFullResponse info) {
    final theme = FluentTheme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text('获奖项目 (${info.awards.length})', style: theme.typography.subtitle),
          ),
          ...info.awards.map((award) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildAwardListItem(context, award),
          )),
        ],
      ),
    );
  }

  Widget _buildAwardListItem(BuildContext context, AwardProject award) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final levelColor = _getLevelColor(award.level, isDark);
    final isSelected = _selectedAward?.projectName == award.projectName;

    return HoverButton(
      onPressed: () => setState(() => _selectedAward = award),
      builder: (context, states) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: states.isHovering
                ? theme.accentColor.withValues(alpha: 0.1)
                : (isSelected ? theme.accentColor.withValues(alpha: 0.15) : null),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? theme.accentColor : theme.resources.controlStrokeColorDefault,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              // 等级图标
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: levelColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(_getLevelIcon(award.level), color: levelColor, size: 20),
              ),
              const SizedBox(width: 12),
              // 项目信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      award.projectName,
                      style: theme.typography.body?.copyWith(fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _buildMiniTag(context, award.level, levelColor),
                        const SizedBox(width: 6),
                        _buildMiniTag(context, award.grade, theme.inactiveColor),
                      ],
                    ),
                  ],
                ),
              ),
              // 学分
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${award.credits.toStringAsFixed(1)}',
                    style: theme.typography.bodyStrong?.copyWith(color: theme.accentColor),
                  ),
                  Text('学分', style: theme.typography.caption?.copyWith(color: theme.inactiveColor)),
                ],
              ),
              const SizedBox(width: 8),
              Icon(FluentIcons.chevron_right, size: 12, color: theme.inactiveColor),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMiniTag(BuildContext context, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }


  /// 构建获奖详情面板
  Widget _buildAwardDetail(BuildContext context, AwardProject award) {
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final levelColor = _getLevelColor(award.level, isDark);
    final verificationColor = _getVerificationColor(award.verificationStatus, isDark);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 返回按钮
          Button(
            onPressed: () => setState(() => _selectedAward = null),
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
          // 项目标题卡片
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
                        color: levelColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(_getLevelIcon(award.level), color: levelColor, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(award.projectName, style: theme.typography.title),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              _buildLevelBadge(context, award.level, levelColor),
                              const SizedBox(width: 8),
                              Text(award.grade, style: theme.typography.body?.copyWith(fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 学分和奖金
          Row(
            children: [
              Expanded(
                child: WinUICard(
                  child: Column(
                    children: [
                      Icon(FluentIcons.education, size: 24, color: theme.accentColor),
                      const SizedBox(height: 8),
                      Text(
                        award.credits.toStringAsFixed(1),
                        style: theme.typography.title?.copyWith(fontWeight: FontWeight.bold, color: theme.accentColor),
                      ),
                      Text('获奖学分', style: theme.typography.caption?.copyWith(color: theme.inactiveColor)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: WinUICard(
                  child: Column(
                    children: [
                      Icon(FluentIcons.money, size: 24, color: isDark ? Colors.orange.light : Colors.orange),
                      const SizedBox(height: 8),
                      Text(
                        award.bonus > 0 ? '¥${award.bonus.toStringAsFixed(0)}' : '-',
                        style: theme.typography.title?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: award.bonus > 0 ? (isDark ? Colors.orange.light : Colors.orange) : theme.inactiveColor,
                        ),
                      ),
                      Text('奖励金额', style: theme.typography.caption?.copyWith(color: theme.inactiveColor)),
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
                Text('详细信息', style: theme.typography.bodyStrong),
                const SizedBox(height: 16),
                _buildDetailRow(context, '获奖日期', award.awardDate),
                const SizedBox(height: 12),
                _buildDetailRow(context, '项目主持人', award.applicantId),
                const SizedBox(height: 12),
                _buildDetailRow(context, '顺序号', '${award.order}'),
                const SizedBox(height: 12),
                _buildDetailRow(context, '项目状态', award.status),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 审核状态
          WinUICard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('审核状态', style: theme.typography.bodyStrong),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: verificationColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: verificationColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(_getVerificationIcon(award.verificationStatus), size: 24, color: verificationColor),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              award.verificationStatus,
                              style: theme.typography.bodyStrong?.copyWith(color: verificationColor),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _getVerificationDescription(award.verificationStatus),
                              style: theme.typography.caption?.copyWith(color: theme.inactiveColor),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLevelBadge(BuildContext context, String level, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        level,
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, String label, String value) {
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
          child: Text(value, style: theme.typography.body?.copyWith(fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }

  Color _getLevelColor(String level, bool isDark) {
    if (level.contains('国家级')) return isDark ? Colors.red.light : Colors.red;
    if (level.contains('省部级') || level.contains('省级')) return isDark ? Colors.orange.light : Colors.orange;
    if (level.contains('校级')) return isDark ? Colors.blue.light : Colors.blue;
    return isDark ? Colors.grey[100] : Colors.grey;
  }

  IconData _getLevelIcon(String level) {
    if (level.contains('国家级')) return FluentIcons.trophy2;
    if (level.contains('省部级') || level.contains('省级')) return FluentIcons.ribbon;
    if (level.contains('校级')) return FluentIcons.education;
    return FluentIcons.trophy2;
  }

  Color _getVerificationColor(String status, bool isDark) {
    if (status.contains('通过')) return isDark ? Colors.green.light : Colors.green;
    if (status.contains('未通过')) return isDark ? Colors.red.light : Colors.red;
    return isDark ? Colors.grey[100] : Colors.grey;
  }

  IconData _getVerificationIcon(String status) {
    if (status.contains('通过')) return FluentIcons.check_mark;
    if (status.contains('未通过')) return FluentIcons.cancel;
    return FluentIcons.clock;
  }

  String _getVerificationDescription(String status) {
    if (status.contains('通过')) return '该项目已通过审核，学分已计入';
    if (status.contains('未通过')) return '该项目审核未通过，请联系相关部门';
    return '该项目正在审核中，请耐心等待';
  }
}
