import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import '../../models/manifest_model.dart';
import '../../services/logger_service.dart';

/// WinUI 风格的 OTA 更新对话框
///
/// 使用 fluent_ui 的 ContentDialog 显示更新信息
/// 支持强制更新和可选更新
class WinUIOTADialog extends StatelessWidget {
  final OTA ota;
  final String currentVersion;
  final String platform;
  final VoidCallback? onDismiss;

  const WinUIOTADialog({
    super.key,
    required this.ota,
    required this.currentVersion,
    required this.platform,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final release = ota.getPlatformRelease(platform);
    if (release == null) {
      return const SizedBox.shrink();
    }

    final isForceUpdate = release.forceOta;
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
              FluentIcons.system,
              color: theme.accentColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Text('发现新版本'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildVersionInfo(context, theme, release.version),
            const SizedBox(height: 20),
            if (ota.content.isNotEmpty) ...[
              _buildSectionTitle(theme, '更新内容'),
              const SizedBox(height: 10),
              _buildContentBox(theme, ota.content),
              const SizedBox(height: 20),
            ],
            if (ota.changelog.isNotEmpty) ...[
              _buildSectionTitle(theme, '更新日志'),
              const SizedBox(height: 10),
              _buildChangelogBox(context, theme),
              const SizedBox(height: 20),
            ],
            _buildSectionTitle(theme, '下载链接'),
            const SizedBox(height: 10),
            _buildDownloadLinkBox(context, theme, release.url),
            const SizedBox(height: 20),
            _buildMd5Box(theme, release.md5),
            if (isForceUpdate) ...[
              const SizedBox(height: 20),
              _buildForceUpdateWarning(),
            ],
          ],
        ),
      ),
      actions: [
        if (!isForceUpdate)
          Button(
            onPressed: () {
              Navigator.pop(context);
              onDismiss?.call();
            },
            child: const Text('稍后更新'),
          ),
        FilledButton(
          onPressed: () => _copyToClipboard(context, release.url),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(FluentIcons.copy, size: 16),
              SizedBox(width: 8),
              Text('复制链接'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVersionInfo(
      BuildContext context, FluentThemeData theme, String newVersion) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.resources.cardStrokeColorDefault,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '当前版本',
                  style: theme.typography.caption?.copyWith(
                    color: theme.inactiveColor,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  currentVersion,
                  style: theme.typography.bodyLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              FluentIcons.forward,
              color: Colors.green,
              size: 16,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '新版本',
                  style: theme.typography.caption?.copyWith(
                    color: theme.inactiveColor,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  newVersion,
                  style: theme.typography.bodyLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(FluentThemeData theme, String title) {
    return Text(
      title,
      style: theme.typography.bodyStrong,
    );
  }

  Widget _buildContentBox(FluentThemeData theme, String content) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.resources.cardStrokeColorDefault,
        ),
      ),
      child: Text(
        content,
        style: theme.typography.body?.copyWith(height: 1.6),
      ),
    );
  }

  Widget _buildChangelogBox(BuildContext context, FluentThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.resources.cardStrokeColorDefault,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: ota.changelog.take(3).map((entry) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'v${entry.version}',
                  style: theme.typography.caption?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.accentColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  entry.changes,
                  style: theme.typography.caption?.copyWith(height: 1.5),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDownloadLinkBox(
      BuildContext context, FluentThemeData theme, String url) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(
          color: theme.resources.cardStrokeColorDefault,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            url,
            style: theme.typography.caption?.copyWith(
              fontFamily: 'monospace',
              color: theme.accentColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '选择复制，或点击下方按钮复制后在浏览器打开',
            style: theme.typography.caption?.copyWith(
              color: theme.inactiveColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMd5Box(FluentThemeData theme, String md5) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor.withValues(alpha: 0.5),
        border: Border.all(
          color: theme.resources.cardStrokeColorDefault,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MD5 校验值',
            style: theme.typography.caption?.copyWith(
              color: theme.inactiveColor,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            md5,
            style: theme.typography.caption?.copyWith(
              fontFamily: 'monospace',
              color: theme.inactiveColor,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForceUpdateWarning() {
    return InfoBar(
      title: const Text('强制更新'),
      content: const Text('此版本为强制更新，您必须更新才能继续使用应用'),
      severity: InfoBarSeverity.warning,
      isLong: true,
    );
  }

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    LoggerService.info('📋 已复制下载链接');

    displayInfoBar(
      context,
      builder: (context, close) {
        return InfoBar(
          title: const Text('已复制'),
          content: const Text('下载链接已复制，请在浏览器中打开下载'),
          severity: InfoBarSeverity.success,
          onClose: close,
        );
      },
      duration: const Duration(seconds: 3),
    );
  }

  /// 显示 OTA 更新对话框
  static Future<void> show(
    BuildContext context, {
    required OTA ota,
    required String currentVersion,
    required String platform,
    VoidCallback? onDismiss,
  }) {
    final release = ota.getPlatformRelease(platform);
    final isForceUpdate = release?.forceOta ?? false;

    return showDialog(
      context: context,
      barrierDismissible: !isForceUpdate,
      builder: (context) => WinUIOTADialog(
        ota: ota,
        currentVersion: currentVersion,
        platform: platform,
        onDismiss: onDismiss,
      ),
    );
  }
}
