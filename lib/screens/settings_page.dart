import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_constants.dart';
import '../providers/theme_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/aac_provider.dart';
import '../providers/manifest_provider.dart';
import '../widgets/adaptive_sliver_app_bar.dart';
import '../widgets/color_palette_dialog.dart';
import '../widgets/background_settings.dart';
import '../widgets/glass_card.dart';
import '../widgets/ota_update_dialog.dart';
import '../services/session_manager.dart';
import 'login_screen.dart';

/// Settings page for managing app preferences and account
///
/// Provides options for:
/// - Theme mode selection (light/dark/system)
/// - Color scheme selection
/// - Account information display
/// - Logout functionality
/// - App information and licenses
///
/// Usage:
/// ```dart
/// Navigator.push(
///   context,
///   MaterialPageRoute(builder: (context) => const SettingsPage()),
/// );
/// ```
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        slivers: [
          const AdaptiveSliverAppBar(title: '设置'),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Appearance settings card
                GlassCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionHeader(context, '外观设置'),
                      _buildThemeModeSelector(context),
                      _buildColorSchemeSelector(context),
                      const SizedBox(height: 16),
                      _buildBackgroundSettings(context),
                      const SizedBox(height: 16),
                      _buildCardOpacitySettings(context),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Account management card
                GlassCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionHeader(context, '账号管理'),
                      _buildAccountInfo(context),
                      _buildResetAACTicketTile(context),
                      _buildLogoutTile(context),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Developer tools card
                GlassCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionHeader(context, '开发者工具'),
                      _buildInvalidateTwfIdTile(context),
                      _buildClearCookiesTile(context),
                      _buildTestVpnRedirectTile(context),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // About card
                GlassCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionHeader(context, '关于'),
                      _buildAboutTile(context),
                      _buildCheckUpdateTile(context),
                      _buildLicenseTile(context),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  /// Build section header
  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// Build theme mode selector
  Widget _buildThemeModeSelector(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return ListTile(
          leading: const Icon(Icons.brightness_6),
          title: const Text('主题模式'),
          subtitle: Text(
            themeProvider.getThemeModeName(themeProvider.themeMode),
          ),
          onTap: () => _showThemeModeDialog(context, themeProvider),
        );
      },
    );
  }

  /// Show theme mode selection dialog
  void _showThemeModeDialog(BuildContext context, ThemeProvider themeProvider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择主题模式'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<ThemeMode>(
              title: const Text('浅色模式'),
              value: ThemeMode.light,
              groupValue: themeProvider.themeMode,
              onChanged: (value) {
                if (value != null) {
                  themeProvider.setThemeMode(value);
                  Navigator.of(context).pop();
                }
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('深色模式'),
              value: ThemeMode.dark,
              groupValue: themeProvider.themeMode,
              onChanged: (value) {
                if (value != null) {
                  themeProvider.setThemeMode(value);
                  Navigator.of(context).pop();
                }
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('跟随系统'),
              value: ThemeMode.system,
              groupValue: themeProvider.themeMode,
              onChanged: (value) {
                if (value != null) {
                  themeProvider.setThemeMode(value);
                  Navigator.of(context).pop();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Build color scheme selector
  Widget _buildColorSchemeSelector(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.palette),
                  const SizedBox(width: 16),
                  Text('颜色方案', style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 16),
              ColorPaletteSelector(
                currentScheme: themeProvider.colorScheme,
                customColor: themeProvider.customColor,
                hasBackground: themeProvider.backgroundPath != null,
                onSchemeSelected: (scheme) {
                  themeProvider.setColorScheme(scheme);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// Build background settings
  Widget _buildBackgroundSettings(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.wallpaper),
                  const SizedBox(width: 16),
                  Text('自定义背景', style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 16),
              BackgroundSettings(
                currentBackgroundPath: themeProvider.backgroundPath,
                currentBlur: themeProvider.backgroundBlur,
                onBackgroundChanged: (path) {
                  themeProvider.setBackgroundPath(path);
                },
                onBlurChanged: (blur) {
                  themeProvider.setBackgroundBlur(blur);
                },
                onColorExtracted: (color) {
                  themeProvider.setCustomColor(color);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// Build card opacity settings
  Widget _buildCardOpacitySettings(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        final hasBackground = themeProvider.backgroundPath != null;

        if (!hasBackground) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 卡片透明度
              _SmoothSlider(
                icon: Icons.credit_card,
                title: '卡片透明度',
                value: themeProvider.cardOpacity,
                min: 0.0,
                max: 1.0,
                divisions: 100,
                formatLabel: (value) => '${(value * 100).toInt()}%',
                onChanged: (value) => themeProvider.setCardOpacity(value),
                onReset: () => themeProvider.resetCardOpacity(),
                resetTooltip: '恢复推荐值',
              ),
              const SizedBox(height: 16),

              // 导航栏透明度
              _SmoothSlider(
                icon: Icons.navigation,
                title: '导航栏透明度',
                value: themeProvider.navigationOpacity,
                min: 0.0,
                max: 1.0,
                divisions: 100,
                formatLabel: (value) => '${(value * 100).toInt()}%',
                onChanged: (value) => themeProvider.setNavigationOpacity(value),
                onReset: () => themeProvider.resetNavigationOpacity(),
                resetTooltip: '恢复推荐值',
              ),
              const SizedBox(height: 16),

              // 标题栏透明度
              _SmoothSlider(
                icon: Icons.title,
                title: '标题栏透明度',
                value: themeProvider.appBarOpacity,
                min: 0.0,
                max: 1.0,
                divisions: 100,
                formatLabel: (value) => '${(value * 100).toInt()}%',
                onChanged: (value) => themeProvider.setAppBarOpacity(value),
                onReset: () => themeProvider.resetAppBarOpacity(),
                resetTooltip: '恢复推荐值',
              ),
              const SizedBox(height: 16),

              // 标题栏模糊度
              _SmoothSlider(
                icon: Icons.blur_on,
                title: '标题栏模糊度',
                value: themeProvider.appBarBlur,
                min: 0.0,
                max: 20.0,
                divisions: 100,
                formatLabel: (value) => value.toStringAsFixed(1),
                onChanged: (value) => themeProvider.setAppBarBlur(value),
                onReset: () => themeProvider.resetAppBarBlur(),
                resetTooltip: '恢复默认值',
              ),
              Text(
                '选择背景后自动计算推荐值，可手动调整或点击刷新按钮恢复',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Build account information tile
  Widget _buildAccountInfo(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        final userId = authProvider.credentials?.userId ?? '未登录';

        return ListTile(
          leading: const Icon(Icons.account_circle),
          title: const Text('当前账号'),
          subtitle: Text(userId),
        );
      },
    );
  }

  /// Build reset AAC ticket tile
  Widget _buildResetAACTicketTile(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.refresh),
      title: const Text('重置爱安财Token'),
      subtitle: const Text('如果爱安财数据加载失败，可尝试重置'),
      onTap: () => _showResetAACTicketDialog(context),
    );
  }

  /// Show reset AAC ticket confirmation dialog
  void _showResetAACTicketDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重置爱安财Token'),
        content: const Text('确定要重置爱安财Token吗？重置后需要重新获取。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();

              try {
                // Import AACProvider at the top if not already imported
                final aacProvider = Provider.of<AACProvider?>(
                  context,
                  listen: false,
                );

                if (aacProvider != null) {
                  await aacProvider.resetTicket();

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('爱安财Token已重置')),
                    );
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('重置失败: $e')));
                }
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// Build invalidate TWFID tile
  Widget _buildInvalidateTwfIdTile(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        return ListTile(
          leading: const Icon(Icons.bug_report),
          title: const Text('使 TWFID 失效'),
          subtitle: const Text('测试 VPN 会话过期和静默重登录'),
          onTap: () => _showInvalidateTwfIdDialog(context, authProvider),
        );
      },
    );
  }

  /// Show invalidate TWFID confirmation dialog
  void _showInvalidateTwfIdDialog(
    BuildContext context,
    AuthProvider authProvider,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('使 TWFID 失效'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('这将使当前的 TWFID Cookie 失效，模拟 VPN 会话过期。'),
            SizedBox(height: 8),
            Text('下次发起请求时会触发静默重登录机制。', style: TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();

              try {
                final connection = authProvider.connection;
                if (connection != null) {
                  // 清除 TWFID Cookie
                  connection.client.clearCookie('TWFID');
                  connection.clientNoRedirect.clearCookie('TWFID');

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✅ TWFID 已失效，下次请求将触发静默重登录'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('❌ 未找到连接实例'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('❌ 操作失败: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// Build clear cookies tile
  Widget _buildClearCookiesTile(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        return ListTile(
          leading: const Icon(Icons.cookie),
          title: const Text('清除所有 Cookies'),
          subtitle: const Text('清除所有 HTTP 客户端的 Cookies'),
          onTap: () => _showClearCookiesDialog(context, authProvider),
        );
      },
    );
  }

  /// Show clear cookies confirmation dialog
  void _showClearCookiesDialog(
    BuildContext context,
    AuthProvider authProvider,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除所有 Cookies'),
        content: const Text('这将清除所有 HTTP 客户端的 Cookies，可能导致需要重新登录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();

              try {
                final connection = authProvider.connection;
                if (connection != null) {
                  // 清除所有 Cookies
                  connection.client.clearCookies();
                  connection.clientNoRedirect.clearCookies();
                  connection.simpleClient.clearCookies();

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✅ 所有 Cookies 已清除'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('❌ 未找到连接实例'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('❌ 操作失败: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// Build test VPN redirect tile
  Widget _buildTestVpnRedirectTile(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        return ListTile(
          leading: const Icon(Icons.vpn_key_off),
          title: const Text('测试 VPN 重定向处理'),
          subtitle: const Text('查看 Cookie 统计和连接状态'),
          onTap: () => _showVpnRedirectTestDialog(context, authProvider),
        );
      },
    );
  }

  /// Show VPN redirect test dialog
  void _showVpnRedirectTestDialog(
    BuildContext context,
    AuthProvider authProvider,
  ) {
    final connection = authProvider.connection;
    if (connection == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ 未找到连接实例'), backgroundColor: Colors.red),
      );
      return;
    }

    // 获取 Cookie 统计
    final clientStats = connection.client.getCookieStats();
    final clientNoRedirectStats = connection.clientNoRedirect.getCookieStats();
    final simpleClientCookies = connection.simpleClient.getAllCookies();

    // 获取 TWFID
    final twfId = connection.twfId;
    final hasTwfIdCookie = connection.client.getCookie('TWFID') != null;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('连接状态'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('TWFID: ${twfId ?? "未设置"}'),
              Text('TWFID Cookie: ${hasTwfIdCookie ? "存在" : "不存在"}'),
              const Divider(),
              const Text('HTTPClient (带重定向):'),
              Text('  域名数: ${clientStats['totalDomains']}'),
              Text('  Cookie数: ${clientStats['totalCookies']}'),
              const SizedBox(height: 8),
              const Text('HTTPClient (无重定向):'),
              Text('  域名数: ${clientNoRedirectStats['totalDomains']}'),
              Text('  Cookie数: ${clientNoRedirectStats['totalCookies']}'),
              const SizedBox(height: 8),
              const Text('SimpleHTTPClient:'),
              Text('  Cookie数: ${simpleClientCookies.length}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// Build logout tile
  Widget _buildLogoutTile(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        return ListTile(
          leading: Icon(
            Icons.logout,
            color: Theme.of(context).colorScheme.error,
          ),
          title: Text(
            '退出登录',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          onTap: () => _showLogoutConfirmDialog(context, authProvider),
        );
      },
    );
  }

  /// Show logout confirmation dialog
  void _showLogoutConfirmDialog(
    BuildContext context,
    AuthProvider authProvider,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认退出'),
        content: const Text('确定要退出登录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();

              // Stop SessionManager before logout
              final sessionManager = Provider.of<SessionManager?>(
                context,
                listen: false,
              );
              sessionManager?.stopSessionCheck();
              sessionManager?.dispose();

              // Clear all session data
              await authProvider.logout();

              // Navigate to login screen
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                  (route) => false, // Remove all previous routes
                );
              }
            },
            child: Text(
              '退出',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  /// Build about tile
  Widget _buildAboutTile(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.info),
      title: const Text('关于应用'),
      subtitle: Text('${AppConstants.appName} v${AppConstants.appVersion}'),
      onTap: () => _showAboutDialog(context),
    );
  }

  /// Build check update tile
  Widget _buildCheckUpdateTile(BuildContext context) {
    return Consumer<ManifestProvider>(
      builder: (context, manifestProvider, child) {
        final isLoading = manifestProvider.state == ManifestState.loading;

        return ListTile(
          leading: isLoading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.system_update),
          title: const Text('检查更新'),
          subtitle: Text(
            isLoading
                ? '正在检查...'
                : manifestProvider.hasOTAUpdate
                    ? '发现新版本 ${manifestProvider.latestVersion}'
                    : '当前已是最新版本',
          ),
          onTap: isLoading ? null : () => _checkForUpdate(context),
        );
      },
    );
  }

  /// Check for update
  Future<void> _checkForUpdate(BuildContext context) async {
    final manifestProvider = Provider.of<ManifestProvider>(context, listen: false);

    await manifestProvider.loadManifest(forceRefresh: true);

    if (!context.mounted) return;

    if (manifestProvider.hasOTAUpdate && manifestProvider.ota != null) {
      showDialog(
        context: context,
        barrierDismissible: !manifestProvider.isForceUpdate,
        builder: (context) => OTAUpdateDialog(
          ota: manifestProvider.ota!,
          currentVersion: manifestProvider.currentVersion,
          platform: manifestProvider.currentPlatform,
        ),
      );
    } else if (manifestProvider.state == ManifestState.error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('检查更新失败: ${manifestProvider.errorMessage}'),
          backgroundColor: Colors.red,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('当前已是最新版本'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  /// Show about dialog
  void _showAboutDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: AppConstants.appName,
      applicationVersion: AppConstants.appVersion,
      applicationIcon: const Icon(Icons.school, size: 48),
      children: [
        const SizedBox(height: 16),
        Text(AppConstants.appDescription),
        const SizedBox(height: 16),
        const Text('开发团队: ${AppConstants.developerName}'),
        const Text('联系邮箱: ${AppConstants.developerEmail}'),
      ],
    );
  }

  /// Build license tile
  Widget _buildLicenseTile(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.description),
      title: const Text('开源许可'),
      onTap: () => _showLicensesPage(context),
    );
  }

  /// Show licenses page
  void _showLicensesPage(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('开源许可')),
          body: ListView.builder(
            itemCount: AppConstants.licenses.length,
            itemBuilder: (context, index) {
              final license = AppConstants.licenses[index];
              return Card(
                margin: const EdgeInsets.all(16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        license.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        license.description,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        license.licenseText,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 丝滑的滑动条组件
///
/// 使用本地状态管理实现即时视觉反馈，只在拖动结束时保存
class _SmoothSlider extends StatefulWidget {
  final IconData icon;
  final String title;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) formatLabel;
  final ValueChanged<double> onChanged;
  final VoidCallback onReset;
  final String resetTooltip;

  const _SmoothSlider({
    required this.icon,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.formatLabel,
    required this.onChanged,
    required this.onReset,
    required this.resetTooltip,
  });

  @override
  State<_SmoothSlider> createState() => _SmoothSliderState();
}

class _SmoothSliderState extends State<_SmoothSlider> {
  double? _localValue;
  bool _isDragging = false;

  double get _currentValue =>
      _isDragging ? (_localValue ?? widget.value) : widget.value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(widget.icon),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                widget.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: widget.onReset,
              tooltip: widget.resetTooltip,
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4.0,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8.0),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16.0),
          ),
          child: Slider(
            value: _currentValue,
            min: widget.min,
            max: widget.max,
            divisions: widget.divisions,
            label: widget.formatLabel(_currentValue),
            onChanged: (value) {
              // 只更新本地状态，不触发 Provider
              setState(() {
                _localValue = value;
                _isDragging = true;
              });
            },
            onChangeEnd: (value) {
              // 拖动结束时保存并清除本地状态
              setState(() {
                _isDragging = false;
                _localValue = null;
              });
              widget.onChanged(value);
            },
          ),
        ),
      ],
    );
  }
}
