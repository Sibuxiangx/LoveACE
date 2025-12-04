import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/session_manager.dart';
import '../constants/app_constants.dart';
import '../widgets/loading_indicator.dart';
import '../widgets/vpn_session_expired_dialog.dart';
import 'login_screen.dart';
import 'main_shell.dart';

/// 启动屏幕/主屏幕
///
/// 应用启动时显示的第一个页面
/// 负责会话恢复和自动登录逻辑
/// 根据会话恢复结果导航到相应页面
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  SessionManager? _sessionManager;

  @override
  void initState() {
    super.initState();
    // 在页面初始化时检查认证状态
    _checkAuthStatus();
  }

  @override
  void dispose() {
    // 清理 SessionManager
    _sessionManager?.dispose();
    super.dispose();
  }

  /// 检查认证状态并恢复会话
  ///
  /// 尝试使用保存的凭证自动登录
  /// 成功：启动 SessionManager 并导航到主页面
  /// 失败：导航到登录页面
  Future<void> _checkAuthStatus() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    // 设置VPN重定向回调（静默重登录失败时触发）
    authProvider.onVpnRedirect = () {
      if (mounted) {
        // 显示会话过期对话框
        VpnSessionExpiredDialog.show(
          context,
          onLogin: () {
            // 导航回登录页面
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const LoginScreen()),
              (route) => false,
            );
          },
        );
      }
    };

    // 尝试从保存的凭证恢复会话
    final restored = await authProvider.restoreSession();

    if (!mounted) return;

    if (restored) {
      // 会话恢复成功，启动 SessionManager
      _sessionManager = SessionManager(authProvider);
      _sessionManager!.startSessionCheck();

      // 导航到主页面，并通过 Provider 传递 SessionManager
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => Provider<SessionManager>.value(
            value: _sessionManager!,
            child: const MainShell(),
          ),
        ),
      );
    } else {
      // 会话恢复失败，导航到登录页面
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 应用 logo
            Image.asset('assets/images/logo.png', width: 120, height: 120),
            const SizedBox(height: 24),

            // 应用标题
            Text(
              AppConstants.appName,
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 8),

            // 副标题
            Text(
              'Better LoveACE',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 48),

            // 加载指示器
            const LoadingIndicator(message: '正在加载', size: 56.0),
          ],
        ),
      ),
    );
  }
}
