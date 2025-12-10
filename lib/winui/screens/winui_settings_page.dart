import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import '../../constants/app_constants.dart';
import '../../providers/theme_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/manifest_provider.dart';
import '../../services/session_manager.dart';
import '../widgets/winui_card.dart';
import 'winui_login_screen.dart';

/// WinUI 风格的设置页面
///
/// 使用 ComboBox 实现主题模式选择
/// 实现背景图片选择和清除功能
/// 实现退出登录功能
/// 显示应用信息和版本
/// 复用 ThemeProvider
/// _Requirements: 7.1, 7.2, 7.3, 7.4_
class WinUISettingsPage extends StatefulWidget {
  const WinUISettingsPage({super.key});

  @override
  State<WinUISettingsPage> createState() => _WinUISettingsPageState();
}

class _WinUISettingsPageState extends State<WinUISettingsPage> {
  @override
  Widget build(BuildContext context) {
    return ScaffoldPage.scrollable(
      header: const PageHeader(
        title: Text('设置'),
      ),
      children: [
        // 外观设置
        _buildAppearanceSection(context),
        const SizedBox(height: 24),
        // 账号管理
        _buildAccountSection(context),
        const SizedBox(height: 24),
        // 关于
        _buildAboutSection(context),
      ],
    );
  }

  /// 构建外观设置部分
  Widget _buildAppearanceSection(BuildContext context) {
    final theme = FluentTheme.of(context);

    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return WinUICard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(FluentIcons.color, size: 20, color: theme.accentColor),
                  const SizedBox(width: 8),
                  Text('外观设置', style: theme.typography.subtitle),
                ],
              ),
              const SizedBox(height: 16),
              // 主题模式选择
              _buildThemeModeSelector(context, themeProvider),
            ],
          ),
        );
      },
    );
  }

  /// 构建主题模式选择器
  Widget _buildThemeModeSelector(BuildContext context, ThemeProvider themeProvider) {
    final theme = FluentTheme.of(context);

    return Row(
      children: [
        Icon(FluentIcons.brightness, size: 16, color: theme.inactiveColor),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('主题模式', style: theme.typography.body?.copyWith(fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Text(
                '选择应用的外观主题',
                style: theme.typography.caption?.copyWith(color: theme.inactiveColor),
              ),
            ],
          ),
        ),
        ComboBox<ThemeMode>(
          value: themeProvider.themeMode,
          items: const [
            ComboBoxItem(value: ThemeMode.system, child: Text('跟随系统')),
            ComboBoxItem(value: ThemeMode.light, child: Text('浅色模式')),
            ComboBoxItem(value: ThemeMode.dark, child: Text('深色模式')),
          ],
          onChanged: (value) {
            if (value != null) {
              themeProvider.setThemeMode(value);
            }
          },
        ),
      ],
    );
  }

  /// 构建账号管理部分
  Widget _buildAccountSection(BuildContext context) {
    final theme = FluentTheme.of(context);

    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        final userId = authProvider.credentials?.userId ?? '未登录';

        return WinUICard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(FluentIcons.contact, size: 20, color: theme.accentColor),
                  const SizedBox(width: 8),
                  Text('账号管理', style: theme.typography.subtitle),
                ],
              ),
              const SizedBox(height: 16),
              // 当前账号
              Row(
                children: [
                  Icon(FluentIcons.account_management, size: 16, color: theme.inactiveColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('当前账号', style: theme.typography.body?.copyWith(fontWeight: FontWeight.w500)),
                        const SizedBox(height: 4),
                        Text(userId, style: theme.typography.caption?.copyWith(color: theme.inactiveColor)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              // 退出登录
              Row(
                children: [
                  Icon(FluentIcons.sign_out, size: 16, color: Colors.red),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('退出登录', style: theme.typography.body?.copyWith(fontWeight: FontWeight.w500, color: Colors.red)),
                        const SizedBox(height: 4),
                        Text('退出当前账号并返回登录页面', style: theme.typography.caption?.copyWith(color: theme.inactiveColor)),
                      ],
                    ),
                  ),
                  Button(
                    style: ButtonStyle(
                      foregroundColor: WidgetStateProperty.all(Colors.red),
                    ),
                    child: const Text('退出'),
                    onPressed: () => _showLogoutDialog(context, authProvider),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// 显示退出登录确认对话框
  Future<void> _showLogoutDialog(BuildContext context, AuthProvider authProvider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('确认退出'),
        content: const Text('确定要退出登录吗？'),
        actions: [
          Button(
            child: const Text('取消'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          FilledButton(
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.all(Colors.red),
            ),
            child: const Text('退出'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      // Stop SessionManager before logout
      final sessionManager = Provider.of<SessionManager?>(context, listen: false);
      sessionManager?.stopSessionCheck();
      sessionManager?.dispose();

      // Clear all session data
      await authProvider.logout();

      // Navigate to login screen
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          FluentPageRoute(builder: (context) => const WinUILoginScreen()),
          (route) => false,
        );
      }
    }
  }

  /// 构建关于部分
  Widget _buildAboutSection(BuildContext context) {
    final theme = FluentTheme.of(context);

    return Consumer<ManifestProvider>(
      builder: (context, manifestProvider, child) {
        final isLoading = manifestProvider.state == ManifestState.loading;

        return WinUICard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(FluentIcons.info, size: 20, color: theme.accentColor),
                  const SizedBox(width: 8),
                  Text('关于', style: theme.typography.subtitle),
                ],
              ),
              const SizedBox(height: 16),
              // 应用信息
              Row(
                children: [
                  Icon(FluentIcons.app_icon_default, size: 16, color: theme.inactiveColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(AppConstants.appName, style: theme.typography.body?.copyWith(fontWeight: FontWeight.w500)),
                        const SizedBox(height: 4),
                        Text('版本 ${AppConstants.appVersion}', style: theme.typography.caption?.copyWith(color: theme.inactiveColor)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              // 检查更新
              Row(
                children: [
                  isLoading
                      ? const SizedBox(width: 16, height: 16, child: ProgressRing(strokeWidth: 2))
                      : Icon(FluentIcons.download, size: 16, color: theme.inactiveColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('检查更新', style: theme.typography.body?.copyWith(fontWeight: FontWeight.w500)),
                        const SizedBox(height: 4),
                        Text(
                          isLoading
                              ? '正在检查...'
                              : manifestProvider.hasOTAUpdate
                                  ? '发现新版本 ${manifestProvider.latestVersion}'
                                  : '当前已是最新版本',
                          style: theme.typography.caption?.copyWith(color: theme.inactiveColor),
                        ),
                      ],
                    ),
                  ),
                  Button(
                    onPressed: isLoading ? null : () => _checkForUpdate(context, manifestProvider),
                    child: const Text('检查'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              // 开发者信息
              Row(
                children: [
                  Icon(FluentIcons.developer_tools, size: 16, color: theme.inactiveColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('开发团队', style: theme.typography.body?.copyWith(fontWeight: FontWeight.w500)),
                        const SizedBox(height: 4),
                        Text(AppConstants.developerName, style: theme.typography.caption?.copyWith(color: theme.inactiveColor)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              // 开源许可
              Row(
                children: [
                  Icon(FluentIcons.certificate, size: 16, color: theme.inactiveColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('开源许可', style: theme.typography.body?.copyWith(fontWeight: FontWeight.w500)),
                        const SizedBox(height: 4),
                        Text('查看第三方库许可证', style: theme.typography.caption?.copyWith(color: theme.inactiveColor)),
                      ],
                    ),
                  ),
                  Button(
                    child: const Text('查看'),
                    onPressed: () => _showLicensesDialog(context),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// 检查更新
  Future<void> _checkForUpdate(BuildContext context, ManifestProvider manifestProvider) async {
    await manifestProvider.loadManifest(forceRefresh: true);

    if (!mounted) return;

    if (manifestProvider.hasOTAUpdate && manifestProvider.ota != null) {
      // 显示更新对话框
      await showDialog(
        context: context,
        barrierDismissible: !manifestProvider.isForceUpdate,
        builder: (context) => ContentDialog(
          title: const Text('发现新版本'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('版本: ${manifestProvider.latestVersion}'),
              const SizedBox(height: 8),
              if (manifestProvider.ota?.changelog.isNotEmpty == true) ...[
                const Text('更新日志:'),
                const SizedBox(height: 4),
                ...manifestProvider.ota!.changelog.take(3).map((entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• ${entry.version}: ${entry.changes}'),
                )),
              ],
            ],
          ),
          actions: [
            if (!manifestProvider.isForceUpdate)
              Button(
                child: const Text('稍后'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            FilledButton(
              child: const Text('更新'),
              onPressed: () {
                Navigator.of(context).pop();
                // TODO: 实现更新逻辑
              },
            ),
          ],
        ),
      );
    } else if (manifestProvider.state == ManifestState.error) {
      displayInfoBar(
        context,
        builder: (context, close) => InfoBar(
          title: const Text('检查更新失败'),
          content: Text(manifestProvider.errorMessage ?? '未知错误'),
          severity: InfoBarSeverity.error,
          onClose: close,
        ),
      );
    } else {
      displayInfoBar(
        context,
        builder: (context, close) => InfoBar(
          title: const Text('当前已是最新版本'),
          severity: InfoBarSeverity.success,
          onClose: close,
        ),
      );
    }
  }

  /// 显示许可证对话框
  void _showLicensesDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('开源许可'),
        content: SizedBox(
          width: 500,
          height: 400,
          child: ListView.builder(
            itemCount: AppConstants.licenses.length,
            itemBuilder: (context, index) {
              final license = AppConstants.licenses[index];
              return Expander(
                header: Text(license.name),
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(license.description, style: FluentTheme.of(context).typography.caption),
                    const SizedBox(height: 8),
                    Text(license.licenseText, style: FluentTheme.of(context).typography.body),
                  ],
                ),
              );
            },
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
}
