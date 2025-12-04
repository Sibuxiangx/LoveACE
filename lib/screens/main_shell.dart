import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../providers/manifest_provider.dart';
import '../widgets/app_background.dart';
import '../widgets/ota_update_dialog.dart';
import '../widgets/announcement_dialog.dart';
import 'academic_page.dart';
import 'aac_page.dart';
import 'term_list_page.dart';
import 'settings_page.dart';
import 'more_page.dart';

/// Main shell with responsive Material 3 navigation
/// Uses NavigationBar in portrait mode and NavigationRail in landscape mode
/// Provides navigation between Academic Info and Settings pages
/// Supports custom background with blur effect
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  int _logoTapCount = 0;
  DateTime? _lastTapTime;
  late AnimationController _logoAnimationController;
  late Animation<double> _logoRotation;
  late Animation<double> _logoScale;

  // Pages corresponding to navigation destinations
  final List<Widget> _pages = [
    const AcademicPage(),
    const AACPage(),
    const TermListPage(),
    const MorePage(),
    const SettingsPage(),
  ];

  bool _hasCheckedManifest = false;

  @override
  void initState() {
    super.initState();
    _logoAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _logoRotation = Tween<double>(begin: 0, end: 2).animate(
      CurvedAnimation(
        parent: _logoAnimationController,
        curve: Curves.elasticOut,
      ),
    );

    _logoScale = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(
        parent: _logoAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    // 在页面初始化后检查 Manifest
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkManifest();
    });
  }

  /// 检查 Manifest（公告和 OTA 更新）
  Future<void> _checkManifest() async {
    if (_hasCheckedManifest) return;
    _hasCheckedManifest = true;

    final manifestProvider = Provider.of<ManifestProvider>(context, listen: false);
    await manifestProvider.loadManifest();

    if (!mounted) return;

    // 优先显示强制更新对话框
    if (manifestProvider.isForceUpdate && manifestProvider.ota != null) {
      _showOTAUpdateDialog(manifestProvider, isForce: true);
      return; // 强制更新时不显示其他对话框
    }

    // 显示新公告
    if (manifestProvider.hasNewAnnouncement && manifestProvider.announcement != null) {
      await _showAnnouncementDialog(manifestProvider);
    }

    // 显示可选更新
    if (manifestProvider.hasOTAUpdate && manifestProvider.ota != null) {
      _showOTAUpdateDialog(manifestProvider, isForce: false);
    }
  }

  /// 显示公告对话框
  Future<void> _showAnnouncementDialog(ManifestProvider manifestProvider) async {
    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: !manifestProvider.announcement!.confirmRequire,
      builder: (context) => AnnouncementDialog(
        announcement: manifestProvider.announcement!,
        onConfirm: () {
          manifestProvider.markAnnouncementAsShown();
        },
      ),
    );
  }

  /// 显示 OTA 更新对话框
  void _showOTAUpdateDialog(ManifestProvider manifestProvider, {required bool isForce}) {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: !isForce,
      builder: (context) => OTAUpdateDialog(
        ota: manifestProvider.ota!,
        currentVersion: manifestProvider.currentVersion,
        platform: manifestProvider.currentPlatform,
      ),
    );
  }

  @override
  void dispose() {
    _logoAnimationController.dispose();
    super.dispose();
  }

  void _handleLogoTap() {
    final now = DateTime.now();

    // 重置计数器如果距离上次点击超过3秒
    if (_lastTapTime != null && now.difference(_lastTapTime!).inSeconds > 3) {
      _logoTapCount = 0;
    }

    _lastTapTime = now;
    _logoTapCount++;

    // 播放旋转动画
    _logoAnimationController.forward(from: 0);

    // 彩蛋触发条件：连续点击7次
    if (_logoTapCount == 7) {
      _showEasterEgg();
      _logoTapCount = 0;
    } else if (_logoTapCount == 3) {
      // 点击3次时给个提示
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('再点 4 次试试？🤔'),
          duration: Duration(milliseconds: 800),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showEasterEgg() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🎉', style: TextStyle(fontSize: 64)),
              const SizedBox(height: 16),
              Text(
                '你发现了隐藏彩蛋！',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                '恭喜你！你是第 ${DateTime.now().millisecondsSinceEpoch % 10000} 位发现这个彩蛋的用户！',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                '❤️ Created By LoveACE Team',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '🌧️ Powered By Sibuxiangx & Flutter',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('太酷了！'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Detect screen orientation for responsive navigation
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        final hasBackground = themeProvider.backgroundPath != null;
        final textColor = hasBackground
            ? themeProvider.navigationTextColor
            : null;
        final iconColor = hasBackground
            ? themeProvider.navigationIconColor
            : null;

        return Theme(
          data: Theme.of(context).copyWith(
            navigationBarTheme: NavigationBarThemeData(
                    backgroundColor: hasBackground ? Colors.transparent : null,
                    elevation: 0,
                    surfaceTintColor: Colors.transparent,
                    indicatorColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withValues(alpha: 0.8),
                    labelTextStyle: WidgetStateProperty.resolveWith((states) {
                      return TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      );
                    }),
                    iconTheme: WidgetStateProperty.resolveWith((states) {
                      return IconThemeData(color: iconColor);
                    }),
                  ),
            navigationRailTheme: hasBackground
                ? NavigationRailThemeData(
                    backgroundColor: Colors.transparent,
                    indicatorColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withValues(alpha: 0.8),
                    labelType: NavigationRailLabelType.all,
                    useIndicator: true,
                    selectedLabelTextStyle: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                    unselectedLabelTextStyle: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: textColor?.withValues(alpha: 0.7),
                    ),
                    selectedIconTheme: IconThemeData(color: iconColor),
                    unselectedIconTheme: IconThemeData(
                      color: iconColor?.withValues(alpha: 0.7),
                    ),
                  )
                : null,
          ),
          child: Scaffold(
            backgroundColor: hasBackground ? Colors.transparent : null,
            body: AppBackground(
              child: Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        // Show NavigationRail in landscape mode
                        if (isLandscape)
                          Container(
                            decoration: hasBackground
                                ? BoxDecoration(
                                    color: Theme.of(context).colorScheme.surface
                                        .withValues(
                                          alpha:
                                              themeProvider.navigationOpacity,
                                        ),
                                    border: Border(
                                      right: BorderSide(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outline
                                            .withValues(alpha: 0.3),
                                        width: 1,
                                      ),
                                    ),
                                  )
                                : null,
                            child: NavigationRail(
                              selectedIndex: _currentIndex,
                              onDestinationSelected: (index) {
                                setState(() {
                                  _currentIndex = index;
                                });
                              },
                              labelType: NavigationRailLabelType.all,
                              useIndicator: true,
                              leading: Padding(
                                padding: const EdgeInsets.only(
                                  top: 16,
                                  bottom: 24,
                                ),
                                child: GestureDetector(
                                  onTap: _handleLogoTap,
                                  child: AnimatedBuilder(
                                    animation: _logoAnimationController,
                                    builder: (context, child) {
                                      return Transform.rotate(
                                        angle: _logoRotation.value * 3.14159,
                                        child: Transform.scale(
                                          scale: _logoScale.value,
                                          child: child,
                                        ),
                                      );
                                    },
                                    child: Container(
                                      width: 56,
                                      height: 56,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primaryContainer
                                            .withValues(alpha: 0.3),
                                      ),
                                      padding: const EdgeInsets.all(8),
                                      child: Image.asset(
                                        'assets/images/logo.png',
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              destinations: const [
                                NavigationRailDestination(
                                  icon: Icon(Icons.school_outlined, size: 28),
                                  selectedIcon: Icon(Icons.school, size: 28),
                                  label: Text('首页'),
                                ),
                                NavigationRailDestination(
                                  icon: Icon(
                                    Icons.volunteer_activism_outlined,
                                    size: 28,
                                  ),
                                  selectedIcon: Icon(
                                    Icons.volunteer_activism,
                                    size: 28,
                                  ),
                                  label: Text('爱安财'),
                                ),
                                NavigationRailDestination(
                                  icon: Icon(Icons.grade_outlined, size: 28),
                                  selectedIcon: Icon(Icons.grade, size: 28),
                                  label: Text('学期成绩'),
                                ),
                                NavigationRailDestination(
                                  icon: Icon(Icons.more_horiz, size: 28),
                                  selectedIcon: Icon(
                                    Icons.more_horiz,
                                    size: 28,
                                  ),
                                  label: Text('更多'),
                                ),
                                NavigationRailDestination(
                                  icon: Icon(Icons.settings_outlined, size: 28),
                                  selectedIcon: Icon(Icons.settings, size: 28),
                                  label: Text('设置'),
                                ),
                              ],
                            ),
                          ),
                        // Main content area
                        Expanded(child: _pages[_currentIndex]),
                      ],
                    ),
                  ),
                  // Show NavigationBar in portrait mode
                  if (!isLandscape)
                    Container(
                      decoration: hasBackground
                          ? BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surface
                                  .withValues(
                                    alpha: themeProvider.navigationOpacity,
                                  ),
                              border: Border(
                                top: BorderSide(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outline
                                      .withValues(alpha: 0.3),
                                  width: 1,
                                ),
                              ),
                            )
                          : null,
                      child: MediaQuery.removePadding(
                        context: context,
                        removeTop: true,
                        child: NavigationBar(
                          selectedIndex: _currentIndex,
                          onDestinationSelected: (index) {
                            setState(() {
                              _currentIndex = index;
                            });
                          },
                          height: 64,
                          destinations: const [
                            NavigationDestination(
                              icon: Icon(Icons.school_outlined),
                              selectedIcon: Icon(Icons.school),
                              label: '首页',
                            ),
                            NavigationDestination(
                              icon: Icon(Icons.volunteer_activism_outlined),
                              selectedIcon: Icon(Icons.volunteer_activism),
                              label: '爱安财',
                            ),
                            NavigationDestination(
                              icon: Icon(Icons.grade_outlined),
                              selectedIcon: Icon(Icons.grade),
                              label: '学期成绩',
                            ),
                            NavigationDestination(
                              icon: Icon(Icons.more_horiz_outlined),
                              selectedIcon: Icon(Icons.more_horiz),
                              label: '更多',
                            ),
                            NavigationDestination(
                              icon: Icon(Icons.settings_outlined),
                              selectedIcon: Icon(Icons.settings),
                              label: '设置',
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
