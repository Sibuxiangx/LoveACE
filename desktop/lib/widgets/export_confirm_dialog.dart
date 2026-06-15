import 'package:flutter/material.dart';

/// 导出确认对话框
///
/// 用于在导出CSV前确认用户是否要强制刷新数据
/// 在横屏模式下会考虑 NavigationRail 的宽度，使对话框居中显示
class ExportConfirmDialog extends StatelessWidget {
  final String title;
  final String content;
  final VoidCallback onConfirm;

  const ExportConfirmDialog({
    super.key,
    required this.title,
    required this.content,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 检测横屏模式
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    // NavigationRail 的默认宽度（Material 3 标准）
    const double navigationRailWidth = 80.0;

    return AlertDialog(
      // 在横屏模式下调整对话框位置，考虑 NavigationRail 的宽度
      insetPadding: isLandscape
          ? EdgeInsets.only(
              left: navigationRailWidth / 2 + 40,
              right: 40,
              top: 40,
              bottom: 40,
            )
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
                  : Theme.of(context).primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.file_download,
              color: isDark
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).primaryColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(title)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              content,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.6,
                    fontSize: 15,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.blue.withValues(alpha: 0.15)
                  : Colors.blue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark
                    ? Colors.blue.shade300.withValues(alpha: 0.3)
                    : Colors.blue.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: isDark ? Colors.blue.shade300 : Colors.blue,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '导出前会自动刷新数据以确保最新',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.blue.shade300 : Colors.blue,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.of(context).pop();
            onConfirm();
          },
          icon: const Icon(Icons.download, size: 18),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          label: const Text('导出'),
        ),
      ],
    );
  }

  /// 显示导出确认对话框
  static Future<void> show(
    BuildContext context, {
    required String title,
    required String content,
    required VoidCallback onConfirm,
  }) async {
    await showDialog(
      context: context,
      builder: (context) => ExportConfirmDialog(
        title: title,
        content: content,
        onConfirm: onConfirm,
      ),
    );
  }
}
