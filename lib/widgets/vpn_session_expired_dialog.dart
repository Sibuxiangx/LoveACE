import 'package:flutter/material.dart';

/// VPN会话过期对话框
///
/// 当VPN会话过期且静默重登录失败时显示
/// 提示用户需要重新登录
class VpnSessionExpiredDialog extends StatelessWidget {
  final VoidCallback onLogin;

  const VpnSessionExpiredDialog({super.key, required this.onLogin});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
      title: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.orange.withValues(alpha: 0.2)
                  : Colors.orange.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.vpn_key_off,
              size: 40,
              color: isDark ? Colors.orange.shade300 : Colors.orange[700],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '会话已过期',
            textAlign: TextAlign.center,
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Text(
            '您的VPN会话已过期，需要重新登录。',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.6,
                  fontSize: 15,
                ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark
                  ? Theme.of(context).colorScheme.surfaceContainerHighest
                  : Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '这可能是由于长时间未操作或网络连接中断导致的。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        FilledButton.icon(
          onPressed: () {
            Navigator.of(context).pop();
            onLogin();
          },
          icon: const Icon(Icons.login, size: 18),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          ),
          label: const Text('重新登录'),
        ),
      ],
    );
  }

  /// 显示VPN会话过期对话框
  static Future<void> show(
    BuildContext context, {
    required VoidCallback onLogin,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false, // 不允许点击外部关闭
      builder: (context) => VpnSessionExpiredDialog(onLogin: onLogin),
    );
  }
}
