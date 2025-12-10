import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/manifest_provider.dart';
import '../widgets/winui_background.dart';
import '../widgets/winui_ota_dialog.dart';
import '../widgets/winui_announcement_dialog.dart';
import 'winui_home_page.dart';
import 'winui_aac_page.dart';
import 'winui_term_list_page.dart';
import 'winui_exam_page.dart';
import 'winui_training_plan_page.dart';
import 'winui_competition_page.dart';
import 'winui_electricity_page.dart';
import 'winui_labor_club_page.dart';
import 'winui_settings_page.dart';
import 'winui_login_screen.dart';

/// WinUI 风格的主导航框架
///
/// 使用 fluent_ui 的 NavigationView 实现侧边栏导航
/// 配置导航项：首页、爱安财、学期成绩、考试安排、培养方案、竞赛获奖、电费查询、劳动俱乐部、设置
/// 左下角用户头像支持切换主题和退出登录
class WinUIMainShell extends StatefulWidget {
  const WinUIMainShell({super.key});

  @override
  State<WinUIMainShell> createState() => _WinUIMainShellState();
}

class _WinUIMainShellState extends State<WinUIMainShell> {
  int _selectedIndex = 0;
  bool _hasCheckedManifest = false;
  final _userMenuController = FlyoutController();

  // 导航项对应的页面
  final List<Widget> _pages = [
    const WinUIHomePage(), // 首页（学业信息）
    const WinUIAACPage(), // 爱安财
    const WinUITermListPage(), // 学期成绩
    const WinUIExamPage(), // 考试安排
    const WinUITrainingPlanPage(), // 培养方案
    const WinUICompetitionPage(), // 竞赛获奖
    const WinUIElectricityPage(), // 电费查询
    const WinUILaborClubPage(), // 劳动俱乐部
    const WinUISettingsPage(), // 设置
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkManifest();
    });
  }

  /// 检查 Manifest（公告和 OTA 更新）
  Future<void> _checkManifest() async {
    if (_hasCheckedManifest) return;
    _hasCheckedManifest = true;

    final manifestProvider =
        Provider.of<ManifestProvider>(context, listen: false);
    await manifestProvider.loadManifest();

    if (!mounted) return;

    // 优先显示强制更新对话框
    if (manifestProvider.isForceUpdate && manifestProvider.ota != null) {
      _showOTAUpdateDialog(manifestProvider, isForce: true);
      return;
    }

    // 显示新公告
    if (manifestProvider.hasNewAnnouncement &&
        manifestProvider.announcement != null) {
      await _showAnnouncementDialog(manifestProvider);
    }

    // 显示可选更新
    if (manifestProvider.hasOTAUpdate && manifestProvider.ota != null) {
      _showOTAUpdateDialog(manifestProvider, isForce: false);
    }
  }

  /// 显示公告对话框
  Future<void> _showAnnouncementDialog(
      ManifestProvider manifestProvider) async {
    if (!mounted) return;

    await WinUIAnnouncementDialog.show(
      context,
      announcement: manifestProvider.announcement!,
      onConfirm: () {
        manifestProvider.markAnnouncementAsShown();
      },
    );
  }

  /// 显示 OTA 更新对话框
  void _showOTAUpdateDialog(ManifestProvider manifestProvider,
      {required bool isForce}) {
    if (!mounted) return;

    WinUIOTADialog.show(
      context,
      ota: manifestProvider.ota!,
      currentVersion: manifestProvider.currentVersion,
      platform: manifestProvider.currentPlatform,
    );
  }

  /// 构建用户菜单 Flyout 内容
  Widget _buildUserMenuFlyout(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final theme = FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final userId = authProvider.credentials?.userId ?? '用户';

    return MenuFlyout(
      items: [
        // 用户信息头部
        MenuFlyoutItem(
          leading: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.accentColor,
            ),
            child: Center(
              child: Text(
                userId.isNotEmpty ? userId[0].toUpperCase() : 'U',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          text: Text(userId),
          onPressed: () {},
        ),
        const MenuFlyoutSeparator(),
        // 主题切换
        MenuFlyoutItem(
          leading: Icon(
            isDark ? FluentIcons.sunny : FluentIcons.clear_night,
            size: 16,
          ),
          text: Text(isDark ? '浅色模式' : '深色模式'),
          onPressed: () {
            _userMenuController.close();
            themeProvider.setThemeMode(
              isDark ? ThemeMode.light : ThemeMode.dark,
            );
          },
        ),
        const MenuFlyoutSeparator(),
        // 退出登录
        MenuFlyoutItem(
          leading: Icon(
            FluentIcons.sign_out,
            size: 16,
            color: Colors.red,
          ),
          text: Text(
            '退出登录',
            style: TextStyle(color: Colors.red),
          ),
          onPressed: () {
            _userMenuController.close();
            _handleLogout(authProvider);
          },
        ),
      ],
    );
  }

  /// 处理退出登录
  Future<void> _handleLogout(AuthProvider authProvider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ContentDialog(
        title: const Text('确认退出'),
        content: const Text('确定要退出登录吗？退出后需要重新登录。'),
        actions: [
          Button(
            child: const Text('取消'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          FilledButton(
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.all(Colors.red),
            ),
            child: const Text('退出'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await authProvider.logout();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          FluentPageRoute(builder: (_) => const WinUILoginScreen()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        return WinUIBackground(
          child: NavigationView(
            pane: NavigationPane(
              selected: _selectedIndex,
              onChanged: (index) => setState(() => _selectedIndex = index),
              displayMode: PaneDisplayMode.compact,
              header: _buildHeader(context),
              items: _buildNavigationItems(),
              footerItems: _buildFooterItems(context),
            ),
          ),
        );
      },
    );
  }

  /// 构建导航头部
  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: FluentTheme.of(context).accentColor.withValues(alpha: 0.2),
            ),
            padding: const EdgeInsets.all(6),
            child: Image.asset(
              'assets/images/logo.png',
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'LoveACE',
            style: FluentTheme.of(context).typography.subtitle,
          ),
        ],
      ),
    );
  }

  /// 构建主导航项
  List<NavigationPaneItem> _buildNavigationItems() {
    return [
      PaneItem(
        icon: const Icon(FluentIcons.home),
        title: const Text('首页'),
        body: _pages[0],
      ),
      PaneItem(
        icon: const Icon(FluentIcons.heart),
        title: const Text('爱安财'),
        body: _pages[1],
      ),
      PaneItem(
        icon: const Icon(FluentIcons.certificate),
        title: const Text('学期成绩'),
        body: _pages[2],
      ),
      PaneItem(
        icon: const Icon(FluentIcons.test_plan),
        title: const Text('考试安排'),
        body: _pages[3],
      ),
      PaneItem(
        icon: const Icon(FluentIcons.education),
        title: const Text('培养方案'),
        body: _pages[4],
      ),
      PaneItem(
        icon: const Icon(FluentIcons.trophy),
        title: const Text('竞赛获奖'),
        body: _pages[5],
      ),
      PaneItem(
        icon: const Icon(FluentIcons.lightning_bolt),
        title: const Text('电费查询'),
        body: _pages[6],
      ),
      PaneItem(
        icon: const Icon(FluentIcons.people),
        title: const Text('劳动俱乐部'),
        body: _pages[7],
      ),
    ];
  }

  /// 构建底部导航项（用户头像 + 设置）
  List<NavigationPaneItem> _buildFooterItems(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.credentials?.userId ?? '用户';

    return [
      // 用户头像按钮
      PaneItemAction(
        icon: FlyoutTarget(
          controller: _userMenuController,
          child: const Icon(FluentIcons.contact),
        ),
        title: Text(userId),
        onTap: () {
          _userMenuController.showFlyout(
            barrierDismissible: true,
            dismissOnPointerMoveAway: false,
            builder: (context) => _buildUserMenuFlyout(context),
          );
        },
      ),
      PaneItemSeparator(),
      PaneItem(
        icon: const Icon(FluentIcons.settings),
        title: const Text('设置'),
        body: _pages[8],
      ),
    ];
  }

  @override
  void dispose() {
    _userMenuController.dispose();
    super.dispose();
  }
}
