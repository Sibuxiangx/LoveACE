import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/session_manager.dart';
import '../../constants/app_constants.dart';
import '../widgets/winui_background.dart';
import '../widgets/winui_dialogs.dart';
import 'winui_login_screen.dart';
import 'winui_main_shell.dart';

/// WinUI 风格的启动页面
///
/// 应用启动时显示的第一个页面
/// 负责会话恢复和自动登录逻辑
/// 根据会话恢复结果导航到相应页面
class WinUIHomeScreen extends StatefulWidget {
  const WinUIHomeScreen({super.key});

  @override
  State<WinUIHomeScreen> createState() => _WinUIHomeScreenState();
}

class _WinUIHomeScreenState extends State<WinUIHomeScreen> {
  SessionManager? _sessionManager;

  @override
  void initState() {
    super.initState();
    // 在页面初始化时检查认证状态
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAuthStatus();
    });
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
        WinUIVpnExpiredDialog.show(
          context,
          onLogin: () {
            // 导航回登录页面
            Navigator.of(context).pushAndRemoveUntil(
              FluentPageRoute(builder: (context) => const WinUILoginScreen()),
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
        FluentPageRoute(
          builder: (context) => Provider<SessionManager>.value(
            value: _sessionManager!,
            child: const WinUIMainShell(),
          ),
        ),
      );
    } else {
      // 会话恢复失败，导航到登录页面
      Navigator.of(context).pushReplacement(
        FluentPageRoute(builder: (context) => const WinUILoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return WinUIBackground(
      child: ScaffoldPage(
        content: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 应用 logo
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.accentColor.withValues(alpha: 0.1),
                ),
                padding: const EdgeInsets.all(16),
                child: Image.asset(
                  'assets/images/logo.png',
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 24),

              // 应用标题
              Text(
                AppConstants.appName,
                style: theme.typography.title,
              ),
              const SizedBox(height: 8),

              // 副标题
              Text(
                'Better LoveACE',
                style: theme.typography.body?.copyWith(
                  color: theme.inactiveColor,
                ),
              ),
              const SizedBox(height: 48),

              // 加载指示器
              const ProgressRing(),
              const SizedBox(height: 16),
              Text(
                '正在加载...',
                style: theme.typography.caption?.copyWith(
                  color: theme.inactiveColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
