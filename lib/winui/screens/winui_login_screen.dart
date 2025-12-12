import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../constants/app_constants.dart';
import '../../services/session_manager.dart';
import '../widgets/winui_background.dart';
import 'winui_main_shell.dart';

/// WinUI 风格的登录页面
///
/// 使用 fluent_ui 组件实现登录表单
/// 支持用户协议确认、密码帮助提示
/// 复用 AuthProvider 进行认证
class WinUILoginScreen extends StatefulWidget {
  const WinUILoginScreen({super.key});

  @override
  State<WinUILoginScreen> createState() => _WinUILoginScreenState();
}

class _WinUILoginScreenState extends State<WinUILoginScreen> {
  final _userIdController = TextEditingController();
  final _ecPasswordController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscureEcPassword = true;
  bool _obscurePassword = true;
  bool _agreedToTerms = false;

  @override
  void dispose() {
    _userIdController.dispose();
    _ecPasswordController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// 显示用户协议对话框
  void _showUserAgreementDialog() {
    showDialog(
      context: context,
      builder: (context) => _WinUIUserAgreementDialog(
        onAgreed: () {
          setState(() {
            _agreedToTerms = true;
          });
        },
      ),
    );
  }

  /// 显示密码帮助对话框
  void _showPasswordHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => const _WinUIPasswordHelpDialog(),
    );
  }

  /// 验证表单
  bool _validateForm() {
    if (_userIdController.text.trim().isEmpty) {
      _showErrorInfoBar('请输入学号');
      return false;
    }
    if (_ecPasswordController.text.isEmpty) {
      _showErrorInfoBar('请输入EC密码');
      return false;
    }
    if (_passwordController.text.isEmpty) {
      _showErrorInfoBar('请输入UAAP密码');
      return false;
    }
    return true;
  }

  /// 显示错误提示
  void _showErrorInfoBar(String message) {
    displayInfoBar(
      context,
      builder: (context, close) {
        return InfoBar(
          title: const Text('提示'),
          content: Text(message),
          severity: InfoBarSeverity.warning,
          action: IconButton(
            icon: const Icon(FluentIcons.clear),
            onPressed: close,
          ),
        );
      },
    );
  }

  /// 处理登录逻辑
  Future<void> _handleLogin() async {
    // 验证表单
    if (!_validateForm()) {
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    // 设置VPN重定向回调（静默重登录失败时触发）
    authProvider.onVpnRedirect = () {
      if (mounted) {
        displayInfoBar(
          context,
          builder: (context, close) {
            return InfoBar(
              title: const Text('会话已过期'),
              content: const Text('请重新登录'),
              severity: InfoBarSeverity.warning,
              action: IconButton(
                icon: const Icon(FluentIcons.clear),
                onPressed: close,
              ),
            );
          },
        );
      }
    };

    // 调用登录方法
    final success = await authProvider.login(
      userId: _userIdController.text.trim(),
      ecPassword: _ecPasswordController.text,
      password: _passwordController.text,
    );

    if (!mounted) return;

    if (success) {
      // 登录成功，创建并启动 SessionManager
      final sessionManager = SessionManager(authProvider);
      sessionManager.startSessionCheck();

      // 导航到主页面
      Navigator.of(context).pushReplacement(
        FluentPageRoute(
          builder: (context) => Provider<SessionManager>.value(
            value: sessionManager,
            child: const WinUIMainShell(),
          ),
        ),
      );
    } else {
      // 登录失败，显示错误消息
      if (mounted) {
        displayInfoBar(
          context,
          builder: (context, close) {
            return InfoBar(
              title: const Text('登录失败'),
              content: Text(authProvider.errorMessage ?? '未知错误'),
              severity: InfoBarSeverity.error,
              action: IconButton(
                icon: const Icon(FluentIcons.clear),
                onPressed: close,
              ),
            );
          },
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return WinUIBackground(
      child: ScaffoldPage(
        content: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 应用 logo
                  Center(
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.accentColor.withValues(alpha: 0.1),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Image.asset(
                        'assets/images/logo.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 应用标题
                  Text(
                    AppConstants.appName,
                    style: theme.typography.title,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'LoveACE makes better!',
                    style: theme.typography.body?.copyWith(
                      color: theme.inactiveColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),

                  // 登录表单卡片
                  Card(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 学号输入框
                        InfoLabel(
                          label: '学号',
                          child: TextBox(
                            controller: _userIdController,
                            placeholder: '请输入学号',
                            prefix: const Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: Icon(FluentIcons.contact, size: 16),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // EC密码输入框
                        InfoLabel(
                          label: 'EC密码',
                          child: TextBox(
                            controller: _ecPasswordController,
                            placeholder: '请输入EC系统密码',
                            obscureText: _obscureEcPassword,
                            prefix: const Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: Icon(FluentIcons.lock, size: 16),
                            ),
                            suffix: IconButton(
                              icon: Icon(
                                _obscureEcPassword
                                    ? FluentIcons.hide3
                                    : FluentIcons.view,
                                size: 16,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscureEcPassword = !_obscureEcPassword;
                                });
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // UAAP密码输入框
                        InfoLabel(
                          label: 'UAAP密码',
                          child: TextBox(
                            controller: _passwordController,
                            placeholder: '请输入UAAP系统密码',
                            obscureText: _obscurePassword,
                            prefix: const Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: Icon(FluentIcons.permissions, size: 16),
                            ),
                            suffix: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? FluentIcons.hide3
                                    : FluentIcons.view,
                                size: 16,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // 用户协议勾选
                        GestureDetector(
                          onTap: () {
                            if (!_agreedToTerms) {
                              _showUserAgreementDialog();
                            } else {
                              setState(() {
                                _agreedToTerms = false;
                              });
                            }
                          },
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Checkbox(
                                checked: _agreedToTerms,
                                onChanged: (value) {
                                  if (value == true && !_agreedToTerms) {
                                    _showUserAgreementDialog();
                                  } else {
                                    setState(() {
                                      _agreedToTerms = value ?? false;
                                    });
                                  }
                                },
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      '我已阅读并同意',
                                      style: theme.typography.caption,
                                    ),
                                    HyperlinkButton(
                                      onPressed: _showUserAgreementDialog,
                                      child: const Text('《用户协议》'),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // 登录按钮
                        Consumer<AuthProvider>(
                          builder: (context, authProvider, child) {
                            final isLoading =
                                authProvider.state == AuthState.loading;
                            return FilledButton(
                              onPressed:
                                  (isLoading || !_agreedToTerms)
                                      ? null
                                      : _handleLogin,
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                child: isLoading
                                    ? const SizedBox(
                                        height: 16,
                                        width: 16,
                                        child: ProgressRing(strokeWidth: 2),
                                      )
                                    : const Text('登录'),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 密码帮助按钮
                  Center(
                    child: HyperlinkButton(
                      onPressed: _showPasswordHelpDialog,
                      child: const Text('登录时遇到问题，不知道密码？'),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // 签名
                  Column(
                    children: [
                      Text(
                        '❤ Created By LoveACE Team',
                        style: theme.typography.caption?.copyWith(
                          color: theme.inactiveColor,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '🌧 Powered By Sibuxiangx & Flutter',
                        style: theme.typography.caption?.copyWith(
                          color: theme.inactiveColor,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


/// WinUI 风格的用户协议对话框
///
/// 需要滚动到底部才能同意
class _WinUIUserAgreementDialog extends StatefulWidget {
  final VoidCallback onAgreed;

  const _WinUIUserAgreementDialog({required this.onAgreed});

  @override
  State<_WinUIUserAgreementDialog> createState() =>
      _WinUIUserAgreementDialogState();
}

class _WinUIUserAgreementDialogState extends State<_WinUIUserAgreementDialog> {
  final ScrollController _scrollController = ScrollController();
  bool _hasScrolledToBottom = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 50) {
      if (!_hasScrolledToBottom) {
        setState(() {
          _hasScrolledToBottom = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return ContentDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              FluentIcons.document,
              color: theme.accentColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Text('用户协议'),
        ],
      ),
      content: SizedBox(
        width: 500,
        height: 400,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                child: SelectableText(
                  AppConstants.userAgreement,
                  style: theme.typography.body,
                ),
              ),
            ),
            if (!_hasScrolledToBottom) ...[
              const SizedBox(height: 8),
              InfoBar(
                title: const Text('请滚动阅读完整协议'),
                severity: InfoBarSeverity.warning,
                isLong: false,
              ),
            ],
          ],
        ),
      ),
      actions: [
        Button(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _hasScrolledToBottom
              ? () {
                  widget.onAgreed();
                  Navigator.of(context).pop();
                }
              : null,
          child: const Text('同意'),
        ),
      ],
    );
  }
}

/// WinUI 风格的密码帮助对话框
class _WinUIPasswordHelpDialog extends StatelessWidget {
  const _WinUIPasswordHelpDialog();

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return ContentDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              FluentIcons.help,
              color: theme.accentColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Text('密码说明'),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // EC密码说明
              Text(
                'EC密码（EasyConnect）',
                style: theme.typography.bodyStrong,
              ),
              const SizedBox(height: 8),
              Text(
                '用于连接校园VPN的密码，登录界面如下图所示：',
                style: theme.typography.body,
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/images/easyconnect.png',
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 16),

              // UAAP密码说明
              Text(
                'UAAP密码',
                style: theme.typography.bodyStrong,
              ),
              const SizedBox(height: 8),
              Text(
                '用于登录教务系统等校内服务的密码，登录界面如下图所示：',
                style: theme.typography.body,
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/images/uaap.png',
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 16),

              // 默认密码提示
              InfoBar(
                title: const Text('默认密码'),
                content: const Text('如果你没有修改过密码，默认密码通常是身份证后六位数字。'),
                severity: InfoBarSeverity.info,
                isLong: true,
              ),
              const SizedBox(height: 12),

              // 忘记密码提示
              InfoBar(
                title: const Text('忘记密码？'),
                content: const Text('建议访问 vpn.aufe.edu.cn 尝试登录来确认密码是否正确。'),
                severity: InfoBarSeverity.warning,
                isLong: true,
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('我知道了'),
        ),
      ],
    );
  }
}
