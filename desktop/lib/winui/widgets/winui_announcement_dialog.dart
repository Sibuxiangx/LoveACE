import 'package:fluent_ui/fluent_ui.dart';
import '../../models/manifest_model.dart';

/// WinUI 风格的公告对话框
///
/// 使用 fluent_ui 的 ContentDialog 显示公告信息
class WinUIAnnouncementDialog extends StatelessWidget {
  final Announcement announcement;
  final VoidCallback? onConfirm;

  const WinUIAnnouncementDialog({
    super.key,
    required this.announcement,
    this.onConfirm,
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
              color: theme.accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              FluentIcons.megaphone,
              color: theme.accentColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              announcement.title,
              style: theme.typography.subtitle,
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: theme.resources.cardStrokeColorDefault,
            ),
          ),
          child: Text(
            announcement.content,
            style: theme.typography.body?.copyWith(
              height: 1.7,
            ),
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () {
            Navigator.pop(context);
            onConfirm?.call();
          },
          child: const Text('我知道了'),
        ),
      ],
    );
  }

  /// 显示公告对话框
  static Future<void> show(
    BuildContext context, {
    required Announcement announcement,
    VoidCallback? onConfirm,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: !announcement.confirmRequire,
      builder: (context) => WinUIAnnouncementDialog(
        announcement: announcement,
        onConfirm: onConfirm,
      ),
    );
  }
}
