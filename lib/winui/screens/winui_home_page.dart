import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import '../../providers/academic_provider.dart';
import '../widgets/winui_card.dart';
import '../widgets/winui_loading.dart';
import '../widgets/winui_empty_state.dart';
import '../widgets/winui_dialogs.dart';

/// WinUI 风格的首页（学业信息）
///
/// 使用 fluent_ui 的 Card 组件展示学业信息
/// 复用 AcademicProvider 进行数据管理
/// 支持加载、错误、空状态处理
/// _Requirements: 3.1, 3.2, 3.3, 3.4, 15.1, 15.2_
class WinUIHomePage extends StatefulWidget {
  const WinUIHomePage({super.key});

  @override
  State<WinUIHomePage> createState() => _WinUIHomePageState();
}

class _WinUIHomePageState extends State<WinUIHomePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    final provider = Provider.of<AcademicProvider>(context, listen: false);
    await provider.loadData(forceRefresh: forceRefresh);

    if (mounted && provider.state == AcademicState.error) {
      _showErrorDialog(provider.errorMessage ?? '加载失败', provider.isRetryable);
    }
  }

  Future<void> _refreshData() async {
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
    return Consumer<AcademicProvider>(
      builder: (context, provider, child) {
        return ScaffoldPage(
          header: PageHeader(
            title: const Text('首页'),
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


  /// 构建页面内容
  Widget _buildContent(BuildContext context, AcademicProvider provider) {
    // 加载中状态
    if (provider.state == AcademicState.loading) {
      return const WinUILoading(message: '正在加载学术信息');
    }

    // 加载完成状态
    if (provider.state == AcademicState.loaded) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildWelcomeSection(context),
            const SizedBox(height: 24),
            _buildAcademicInfoCard(context, provider),
            const SizedBox(height: 16),
            _buildTrainingPlanCard(context, provider),
          ],
        ),
      );
    }

    // 错误状态
    if (provider.state == AcademicState.error) {
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

  /// 构建欢迎区域
  Widget _buildWelcomeSection(BuildContext context) {
    final theme = FluentTheme.of(context);
    final hour = DateTime.now().hour;
    String greeting;
    IconData greetingIcon;

    if (hour < 6) {
      greeting = '夜深了';
      greetingIcon = FluentIcons.clear_night;
    } else if (hour < 12) {
      greeting = '早上好';
      greetingIcon = FluentIcons.sunny;
    } else if (hour < 18) {
      greeting = '下午好';
      greetingIcon = FluentIcons.sunny;
    } else {
      greeting = '晚上好';
      greetingIcon = FluentIcons.clear_night;
    }

    return Row(
      children: [
        Icon(
          greetingIcon,
          size: 32,
          color: theme.accentColor,
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              greeting,
              style: theme.typography.title,
            ),
            Text(
              '欢迎使用 LoveACE',
              style: theme.typography.body?.copyWith(
                color: theme.inactiveColor,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 构建学业信息卡片
  Widget _buildAcademicInfoCard(BuildContext context, AcademicProvider provider) {
    final theme = FluentTheme.of(context);
    final info = provider.academicInfo!;

    return WinUICard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                FluentIcons.education,
                size: 20,
                color: theme.accentColor,
              ),
              const SizedBox(width: 8),
              Text(
                '学业信息',
                style: theme.typography.subtitle,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoRow(context, '当前学期', info.currentTermName),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  context,
                  label: '已修',
                  value: '${info.completedCourses}',
                  unit: '门',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  context,
                  label: '不及格',
                  value: '${info.failedCourses}',
                  unit: '门',
                  valueColor: info.failedCourses > 0 ? Colors.red : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  context,
                  label: '待修',
                  value: '${info.pendingCourses}',
                  unit: '门',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoRow(context, '平均绩点', info.gpa.toStringAsFixed(2)),
        ],
      ),
    );
  }


  /// 构建培养方案卡片
  Widget _buildTrainingPlanCard(BuildContext context, AcademicProvider provider) {
    final theme = FluentTheme.of(context);
    final info = provider.trainingPlanInfo!;

    return WinUICard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                FluentIcons.book_answers,
                size: 20,
                color: theme.accentColor,
              ),
              const SizedBox(width: 8),
              Text(
                '培养方案',
                style: theme.typography.subtitle,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildLabelValueRow(context, '年级', '${info.grade}级'),
          const SizedBox(height: 8),
          _buildLabelValueRow(context, '专业', info.majorName),
          const SizedBox(height: 8),
          _buildLabelValueRow(context, '方案', info.planName),
        ],
      ),
    );
  }

  /// 构建信息行（键值对，左右布局）
  Widget _buildInfoRow(BuildContext context, String label, String value) {
    final theme = FluentTheme.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.typography.body?.copyWith(
            color: theme.inactiveColor,
          ),
        ),
        Text(
          value,
          style: theme.typography.body?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  /// 构建标签值行（标签固定宽度，适合长文本）
  Widget _buildLabelValueRow(BuildContext context, String label, String value) {
    final theme = FluentTheme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 48,
          child: Text(
            label,
            style: theme.typography.body?.copyWith(
              color: theme.inactiveColor,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: theme.typography.body?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  /// 构建统计卡片
  Widget _buildStatCard(
    BuildContext context, {
    required String label,
    required String value,
    required String unit,
    Color? valueColor,
  }) {
    final theme = FluentTheme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.resources.controlStrokeColorDefault,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: theme.typography.caption?.copyWith(
              color: theme.inactiveColor,
            ),
          ),
          const SizedBox(height: 4),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: theme.typography.title?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: valueColor,
                  ),
                ),
                TextSpan(
                  text: ' $unit',
                  style: theme.typography.caption?.copyWith(
                    color: theme.inactiveColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
