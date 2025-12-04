import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../constants/app_constants.dart';
import '../services/session_manager.dart';
import 'main_shell.dart';

/// 登录页面
///
/// 提供学号、EC密码和UAAP密码输入框
/// 支持密码显示/隐藏切换
/// 实现表单验证和登录功能
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
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
      builder: (context) => _UserAgreementDialog(
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
      builder: (context) => Dialog(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题
                  Row(
                    children: [
                      Icon(
                        Icons.help_outline,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '密码说明',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // EC密码说明
                  Text(
                    'EC密码（EasyConnect）',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '用于连接校园VPN的密码，登录界面如下图所示：',
                    style: Theme.of(context).textTheme.bodyMedium,
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
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '用于登录教务系统等校内服务的密码，登录界面如下图所示：',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/images/uaap.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 默认密码提示
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 18,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '默认密码',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '如果你没有修改过密码，默认密码通常是后六位数字。',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 忘记密码提示
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.lightbulb_outline,
                              size: 18,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '忘记密码？',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '建议访问 vpn.aufe.edu.cn 尝试登录来确认密码是否正确。',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 关闭按钮
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('我知道了'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 处理登录逻辑
  Future<void> _handleLogin() async {
    // 验证表单
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    // 设置VPN重定向回调（静默重登录失败时触发）
    authProvider.onVpnRedirect = () {
      if (mounted) {
        // 在登录页面，只显示提示信息
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('会话已过期，请重新登录'),
            backgroundColor: Colors.orange,
          ),
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

      // 导航到主页面，并通过 Provider 传递 SessionManager
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => Provider<SessionManager>.value(
            value: sessionManager,
            child: const MainShell(),
          ),
        ),
      );
    } else {
      // 登录失败，显示错误消息
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authProvider.errorMessage ?? '登录失败'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 应用 logo
                  Center(
                    child: Image.asset(
                      'assets/images/logo.png',
                      width: 100,
                      height: 100,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 应用标题
                  Text(
                    AppConstants.appName,
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'LoveACE makes better!',
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),

                  // 学号输入框
                  TextFormField(
                    controller: _userIdController,
                    decoration: const InputDecoration(
                      labelText: '学号',
                      hintText: '请输入学号',
                      prefixIcon: Icon(Icons.person),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return '请输入学号';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // EC密码输入框
                  TextFormField(
                    controller: _ecPasswordController,
                    decoration: InputDecoration(
                      labelText: 'EC密码',
                      hintText: '请输入EC系统密码',
                      prefixIcon: const Icon(Icons.lock),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureEcPassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscureEcPassword = !_obscureEcPassword;
                          });
                        },
                      ),
                    ),
                    obscureText: _obscureEcPassword,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return '请输入EC密码';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // UAAP密码输入框
                  TextFormField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: 'UAAP密码',
                      hintText: '请输入UAAP系统密码',
                      prefixIcon: const Icon(Icons.vpn_key),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                    ),
                    obscureText: _obscurePassword,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return '请输入UAAP密码';
                      }
                      return null;
                    },
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
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Checkbox(
                            value: _agreedToTerms,
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
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                '我已阅读并同意',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              Text(
                                '《用户协议》',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                ),
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
                      final isLoading = authProvider.state == AuthState.loading;
                      return ElevatedButton(
                        onPressed: (isLoading || !_agreedToTerms) ? null : _handleLogin,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('登录', style: TextStyle(fontSize: 16)),
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  // 密码帮助按钮
                  TextButton.icon(
                    onPressed: _showPasswordHelpDialog,
                    icon: Icon(
                      Icons.help_outline,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    label: Text(
                      '不知道密码是什么？',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 签名
                  Column(
                    children: [
                      Text(
                        '❤ Created By LoveACE Team',
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '🌧 Powered By Sibuxiangx & Flutter',
                        style: Theme.of(context).textTheme.bodySmall,
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


/// 用户协议对话框组件
/// 需要滚动到底部才能同意
class _UserAgreementDialog extends StatefulWidget {
  final VoidCallback onAgreed;

  const _UserAgreementDialog({required this.onAgreed});

  @override
  State<_UserAgreementDialog> createState() => _UserAgreementDialogState();
}

class _UserAgreementDialogState extends State<_UserAgreementDialog> {
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
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.description_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          const Text('用户协议'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                child: Text(
                  AppConstants.userAgreement,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
            if (!_hasScrolledToBottom) ...[
              const SizedBox(height: 8),
              Text(
                '请滚动阅读完整协议',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
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
