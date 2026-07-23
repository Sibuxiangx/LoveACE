import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/manifest_model.dart';
import '../../services/analytics_service.dart';
import '../../services/desktop_update_service.dart';
import '../../services/logger_service.dart';

class WinUIOTADialog extends StatefulWidget {
  final ManifestRelease release;
  final ReleaseArtifact artifact;
  final String currentVersion;
  final String platform;
  final bool forceUpdate;
  final VoidCallback? onDismiss;

  const WinUIOTADialog({
    super.key,
    required this.release,
    required this.artifact,
    required this.currentVersion,
    required this.platform,
    required this.forceUpdate,
    this.onDismiss,
  });

  @override
  State<WinUIOTADialog> createState() => _WinUIOTADialogState();

  static Future<void> show(
    BuildContext context, {
    required ManifestRelease release,
    required ReleaseArtifact artifact,
    required String currentVersion,
    required String platform,
    required bool forceUpdate,
    VoidCallback? onDismiss,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      dismissWithEsc: false,
      builder: (context) => WinUIOTADialog(
        release: release,
        artifact: artifact,
        currentVersion: currentVersion,
        platform: platform,
        forceUpdate: forceUpdate,
        onDismiss: onDismiss,
      ),
    );
  }
}

class _WinUIOTADialogState extends State<WinUIOTADialog> {
  final _updateService = DesktopUpdateService();

  bool _isDownloading = false;
  bool _installerStarted = false;
  double _downloadProgress = 0;
  String? _downloadError;

  bool get _isMacOS => widget.platform.toLowerCase() == 'macos';

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return PopScope(
      canPop: !widget.forceUpdate && !_isDownloading,
      child: ContentDialog(
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
              _buildVersionInfo(theme),
              if (widget.release.summary.isNotEmpty) ...[
                const SizedBox(height: 20),
                _buildSectionTitle(theme, '更新内容'),
                const SizedBox(height: 10),
                _buildContentBox(theme, widget.release.summary),
              ],
              if (widget.release.changelog.isNotEmpty) ...[
                const SizedBox(height: 20),
                _buildSectionTitle(theme, '更新日志'),
                const SizedBox(height: 10),
                _buildChangelogBox(theme),
              ],
              if (_isMacOS) ...[
                const SizedBox(height: 20),
                const InfoBar(
                  title: Text('macOS 手动安装'),
                  content: Text(
                    '下载 ZIP 后退出当前应用，解压并用新的 loveace.app 替换“应用程序”中的旧版本。',
                  ),
                  severity: InfoBarSeverity.info,
                  isLong: true,
                ),
              ],
              if (_isDownloading) ...[
                const SizedBox(height: 20),
                Text('正在下载安装程序 ${(_downloadProgress * 100).round()}%'),
                const SizedBox(height: 8),
                ProgressBar(value: _downloadProgress * 100),
              ],
              if (_installerStarted) ...[
                const SizedBox(height: 20),
                const InfoBar(
                  title: Text('安装程序已启动'),
                  content: Text('请按照安装程序提示完成更新；安装程序将处理正在运行的 LoveACE。'),
                  severity: InfoBarSeverity.success,
                  isLong: true,
                ),
              ],
              if (_downloadError != null) ...[
                const SizedBox(height: 20),
                InfoBar(
                  title: const Text('更新失败'),
                  content: Text(_downloadError!),
                  severity: InfoBarSeverity.error,
                  isLong: true,
                ),
              ],
              const SizedBox(height: 20),
              _buildSectionTitle(theme, '下载链接'),
              const SizedBox(height: 10),
              _buildDownloadLinkBox(theme),
              if (widget.artifact.checksums.sha256?.isNotEmpty == true) ...[
                const SizedBox(height: 12),
                _buildChecksumBox(
                  theme,
                  'SHA-256',
                  widget.artifact.checksums.sha256!,
                ),
              ],
              if (widget.artifact.checksums.md5?.isNotEmpty == true) ...[
                const SizedBox(height: 12),
                _buildChecksumBox(theme, 'MD5', widget.artifact.checksums.md5!),
              ],
              if (widget.forceUpdate) ...[
                const SizedBox(height: 20),
                const InfoBar(
                  title: Text('强制更新'),
                  content: Text('此版本为强制更新，您必须更新才能继续使用应用'),
                  severity: InfoBarSeverity.warning,
                  isLong: true,
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (!widget.forceUpdate)
            Button(
              onPressed: _isDownloading
                  ? null
                  : () {
                      Navigator.pop(context);
                      widget.onDismiss?.call();
                    },
              child: const Text('稍后更新'),
            ),
          FilledButton(
            onPressed: _isDownloading || _installerStarted
                ? null
                : () async {
                    AnalyticsService.instance.trackOtaUpdateClick(
                      widget.currentVersion,
                      widget.release.version,
                    );
                    if (_isMacOS) {
                      await _openInBrowser();
                    } else {
                      await _downloadAndLaunchWindowsInstaller();
                    }
                  },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isMacOS
                      ? FluentIcons.open_in_new_window
                      : FluentIcons.download,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  _isMacOS
                      ? '浏览器下载'
                      : _isDownloading
                      ? '下载中'
                      : '下载并安装',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVersionInfo(FluentThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.resources.cardStrokeColorDefault),
      ),
      child: Row(
        children: [
          Expanded(
            child: _versionColumn(theme, '当前版本', widget.currentVersion, false),
          ),
          Icon(FluentIcons.forward, color: Colors.green, size: 16),
          Expanded(
            child: _versionColumn(theme, '新版本', widget.release.version, true),
          ),
        ],
      ),
    );
  }

  Widget _versionColumn(
    FluentThemeData theme,
    String label,
    String version,
    bool trailing,
  ) {
    return Column(
      crossAxisAlignment: trailing
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.typography.caption?.copyWith(color: theme.inactiveColor),
        ),
        const SizedBox(height: 6),
        Text(
          version,
          style: theme.typography.bodyLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: trailing ? Colors.green : null,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(FluentThemeData theme, String title) =>
      Text(title, style: theme.typography.bodyStrong);

  Widget _buildContentBox(FluentThemeData theme, String content) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.resources.cardStrokeColorDefault),
      ),
      child: Text(content, style: theme.typography.body?.copyWith(height: 1.6)),
    );
  }

  Widget _buildChangelogBox(FluentThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.resources.cardStrokeColorDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: widget.release.changelog
            .map(
              (change) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '• $change',
                  style: theme.typography.caption?.copyWith(height: 1.5),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildDownloadLinkBox(FluentThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: theme.resources.cardStrokeColorDefault),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        widget.artifact.url,
        style: theme.typography.caption?.copyWith(
          fontFamily: 'monospace',
          color: theme.accentColor,
        ),
      ),
    );
  }

  Widget _buildChecksumBox(FluentThemeData theme, String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor.withValues(alpha: 0.5),
        border: Border.all(color: theme.resources.cardStrokeColorDefault),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label 校验值',
            style: theme.typography.caption?.copyWith(
              color: theme.inactiveColor,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            value,
            style: theme.typography.caption?.copyWith(
              fontFamily: 'monospace',
              color: theme.inactiveColor,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openInBrowser() async {
    try {
      final launched = await launchUrl(
        Uri.parse(widget.artifact.url),
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) _copyToClipboard();
    } catch (error) {
      LoggerService.error('❌ 无法打开下载链接', error: error);
      if (mounted) _copyToClipboard();
    }
  }

  Future<void> _downloadAndLaunchWindowsInstaller() async {
    String? destination;
    try {
      destination = await _updateService.chooseWindowsInstallerPath(
        widget.release,
      );
    } catch (error) {
      LoggerService.error('❌ 无法选择安装程序保存位置', error: error);
      if (mounted) setState(() => _downloadError = error.toString());
      return;
    }
    if (destination == null || !mounted) return;

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
      _downloadError = null;
    });
    try {
      await _updateService.downloadWindowsInstaller(
        widget.artifact,
        destination,
        onProgress: (progress) {
          if (mounted) setState(() => _downloadProgress = progress);
        },
      );
      await _updateService.launchWindowsInstaller(destination);
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadProgress = 1;
          _installerStarted = true;
        });
      }
    } catch (error) {
      LoggerService.error('❌ Windows 更新失败', error: error);
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadError = error.toString();
        });
      }
    }
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: widget.artifact.url));
    LoggerService.info('📋 已复制下载链接');
    displayInfoBar(
      context,
      builder: (context, close) => InfoBar(
        title: const Text('已复制'),
        content: const Text('下载链接已复制，请在浏览器中打开下载'),
        severity: InfoBarSeverity.success,
        onClose: close,
      ),
      duration: const Duration(seconds: 3),
    );
  }
}
