import 'package:flutter/material.dart';

/// 智能错误对话框
///
/// 根据错误是否可重试来决定显示重试按钮还是关闭按钮
/// 满足需求: 13.1, 13.2, 13.3, 13.4, 13.5
class RetryableErrorDialog extends StatelessWidget {
  /// 错误消息
  final String message;

  /// 是否可重试
  final bool retryable;

  /// 重试回调函数
  final VoidCallback? onRetry;

  const RetryableErrorDialog({
    super.key,
    required this.message,
    required this.retryable,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
      title: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.error.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.error_outline,
              size: 40,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '加载失败',
            textAlign: TextAlign.center,
          ),
        ],
      ),
      content: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                height: 1.6,
                fontSize: 15,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        // 根据是否可重试显示不同的按钮文本
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          child: Text(retryable ? '取消' : '关闭'),
        ),
        // 如果可重试且提供了重试回调，显示重试按钮
        if (retryable && onRetry != null)
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              onRetry!();
            },
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('重试'),
          ),
      ],
    );
  }
}
