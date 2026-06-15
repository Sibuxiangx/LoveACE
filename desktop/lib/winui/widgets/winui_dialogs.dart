import 'package:fluent_ui/fluent_ui.dart';

/// WinUI 风格的错误对话框
///
/// 使用 fluent_ui 的 ContentDialog 显示错误信息
/// 支持可重试和不可重试两种模式
class WinUIErrorDialog extends StatelessWidget {
  /// 错误标题
  final String title;

  /// 错误消息
  final String message;

  /// 是否可重试
  final bool retryable;

  /// 重试回调函数
  final VoidCallback? onRetry;

  const WinUIErrorDialog({
    super.key,
    this.title = '加载失败',
    required this.message,
    this.retryable = false,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return ContentDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              FluentIcons.error_badge,
              color: Colors.red,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Text(title),
        ],
      ),
      content: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          message,
          style: theme.typography.body,
        ),
      ),
      actions: [
        Button(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(retryable ? '取消' : '关闭'),
        ),
        if (retryable && onRetry != null)
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              onRetry!();
            },
            child: const Text('重试'),
          ),
      ],
    );
  }

  /// 显示错误对话框
  static Future<void> show(
    BuildContext context, {
    String title = '加载失败',
    required String message,
    bool retryable = false,
    VoidCallback? onRetry,
  }) {
    return showDialog(
      context: context,
      builder: (context) => WinUIErrorDialog(
        title: title,
        message: message,
        retryable: retryable,
        onRetry: onRetry,
      ),
    );
  }
}

/// WinUI 风格的确认对话框
///
/// 使用 fluent_ui 的 ContentDialog 显示确认信息
class WinUIConfirmDialog extends StatelessWidget {
  /// 对话框标题
  final String title;

  /// 对话框内容
  final String content;

  /// 确认按钮文本
  final String confirmText;

  /// 取消按钮文本
  final String cancelText;

  /// 是否为危险操作
  final bool isDangerous;

  const WinUIConfirmDialog({
    super.key,
    required this.title,
    required this.content,
    this.confirmText = '确认',
    this.cancelText = '取消',
    this.isDangerous = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return ContentDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDangerous
                  ? Colors.red.withValues(alpha: 0.15)
                  : theme.accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isDangerous ? FluentIcons.warning : FluentIcons.info,
              color: isDangerous ? Colors.red : theme.accentColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(title)),
        ],
      ),
      content: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          content,
          style: theme.typography.body,
        ),
      ),
      actions: [
        Button(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelText),
        ),
        FilledButton(
          style: isDangerous
              ? ButtonStyle(
                  backgroundColor: WidgetStateProperty.all(Colors.red),
                )
              : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmText),
        ),
      ],
    );
  }

  /// 显示确认对话框
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String content,
    String confirmText = '确认',
    String cancelText = '取消',
    bool isDangerous = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => WinUIConfirmDialog(
        title: title,
        content: content,
        confirmText: confirmText,
        cancelText: cancelText,
        isDangerous: isDangerous,
      ),
    );
    return result ?? false;
  }
}

/// WinUI 风格的 VPN 会话过期对话框
///
/// 当 VPN 会话过期时显示，提示用户重新登录
class WinUIVpnExpiredDialog extends StatelessWidget {
  /// 重新登录回调
  final VoidCallback onLogin;

  const WinUIVpnExpiredDialog({
    super.key,
    required this.onLogin,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return ContentDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              FluentIcons.permissions,
              color: Colors.orange,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Text('会话已过期'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text(
            '您的 VPN 会话已过期，需要重新登录。',
            style: theme.typography.body,
          ),
          const SizedBox(height: 16),
          InfoBar(
            title: const Text('提示'),
            content: const Text('这可能是由于长时间未操作或网络连接中断导致的。'),
            severity: InfoBarSeverity.info,
            isLong: true,
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop();
            onLogin();
          },
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(FluentIcons.signin, size: 16),
              SizedBox(width: 8),
              Text('重新登录'),
            ],
          ),
        ),
      ],
    );
  }

  /// 显示 VPN 会话过期对话框
  static Future<void> show(
    BuildContext context, {
    required VoidCallback onLogin,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => WinUIVpnExpiredDialog(onLogin: onLogin),
    );
  }
}
