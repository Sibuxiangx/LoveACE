import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/manifest_model.dart';
import '../services/logger_service.dart';

/// OTA 更新对话框
class OTAUpdateDialog extends StatelessWidget {
  final OTA ota;
  final String currentVersion;
  final String platform;
  final VoidCallback? onDismiss;

  const OTAUpdateDialog({
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: !isForceUpdate,
      child: AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
        actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark
                    ? Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.15)
                    : Theme.of(context).primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.system_update,
                color: isDark
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).primaryColor,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            const Text('发现新版本'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildVersionInfo(context, isDark, release.version),
              const SizedBox(height: 20),
              if (ota.content.isNotEmpty) ...[
                _buildSectionTitle(context, '更新内容'),
                const SizedBox(height: 10),
                _buildContentBox(context, isDark, ota.content),
                const SizedBox(height: 20),
              ],
              if (ota.changelog.isNotEmpty) ...[
                _buildSectionTitle(context, '更新日志'),
                const SizedBox(height: 10),
                _buildChangelogBox(context, isDark),
                const SizedBox(height: 20),
              ],
              _buildSectionTitle(context, '下载链接'),
              const SizedBox(height: 10),
              _buildDownloadLinkBox(context, isDark, release.url),
              const SizedBox(height: 20),
              _buildMd5Box(context, isDark, release.md5),
              if (isForceUpdate) ...[
                const SizedBox(height: 20),
                _buildForceUpdateWarning(context, isDark),
              ],
            ],
          ),
        ),
        actions: [
          if (!isForceUpdate)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                onDismiss?.call();
              },
              child: const Text('稍后更新'),
            ),
          FilledButton.icon(
            onPressed: () => _copyToClipboard(context, release.url),
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('复制链接'),
          ),
        ],
      ),
    );
  }

  Widget _buildVersionInfo(BuildContext context, bool isDark, String newVersion) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('当前版本',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12)),
                const SizedBox(height: 6),
                Text(currentVersion,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold, fontSize: 17)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.green.withValues(alpha: 0.15)
                  : Colors.green.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.arrow_forward,
                color: isDark ? Colors.green.shade300 : Colors.green, size: 18),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('新版本',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12)),
                const SizedBox(height: 6),
                Text(newVersion,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                        color: isDark ? Colors.green.shade300 : Colors.green)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(title,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(fontWeight: FontWeight.bold));
  }

  Widget _buildContentBox(BuildContext context, bool isDark, String content) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(content,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(height: 1.6, fontSize: 14)),
    );
  }

  Widget _buildChangelogBox(BuildContext context, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: ota.changelog.take(3).map((entry) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('v${entry.version}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: isDark
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).primaryColor)),
                const SizedBox(height: 4),
                Text(entry.changes,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(height: 1.5, fontSize: 13)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDownloadLinkBox(BuildContext context, bool isDark, String url) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : Colors.grey[100],
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            url,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontSize: 11,
                color: isDark
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).primaryColor),
          ),
          const SizedBox(height: 8),
          Text('长按可选择复制，或点击下方按钮复制后在浏览器打开',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildMd5Box(BuildContext context, bool isDark, String md5) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.5)
            : Colors.grey[50],
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('MD5 校验值',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12)),
          const SizedBox(height: 6),
          SelectableText(md5,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  letterSpacing: 0.5)),
        ],
      ),
    );
  }

  Widget _buildForceUpdateWarning(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.orange.withValues(alpha: 0.15)
            : Colors.orange[50],
        border: Border.all(
            color: isDark
                ? Colors.orange.shade300.withValues(alpha: 0.5)
                : Colors.orange[300]!),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded,
              color: isDark ? Colors.orange.shade300 : Colors.orange[700],
              size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text('此版本为强制更新，您必须更新才能继续使用应用',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isDark ? Colors.orange.shade300 : Colors.orange[700],
                    fontSize: 13,
                    height: 1.4)),
          ),
        ],
      ),
    );
  }

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    LoggerService.info('📋 已复制下载链接');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('下载链接已复制，请在浏览器中打开下载'),
        duration: Duration(seconds: 3),
      ),
    );
  }
}
