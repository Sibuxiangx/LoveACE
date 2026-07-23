import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/manifest_model.dart';
import '../services/analytics_service.dart';
import '../services/logger_service.dart';
import '../services/manifest_service.dart';

enum ManifestState { initial, loading, loaded, error }

class ManifestProvider extends ChangeNotifier {
  static const _dismissedNoticeIDsKey = 'dismissed_manifest_notice_ids';

  final ManifestService _service;
  final SharedPreferences _prefs;
  final String _currentVersion;
  final int _currentBuild;

  ManifestState _state = ManifestState.initial;
  ManifestV2? _manifest;
  String? _errorMessage;
  List<ManifestNotice> _pendingNotices = const [];

  factory ManifestProvider({
    required ManifestService service,
    required SharedPreferences prefs,
    required String currentVersion,
    required int currentBuild,
  }) => ManifestProvider._(service, prefs, currentVersion, currentBuild);

  ManifestProvider._(
    this._service,
    this._prefs,
    this._currentVersion,
    this._currentBuild,
  );

  ManifestState get state => _state;
  ManifestV2? get manifest => _manifest;
  String? get errorMessage => _errorMessage;
  String get currentVersion => _currentVersion;
  int get currentBuild => _currentBuild;

  String get currentPlatform {
    if (kIsWeb) return 'web';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  PlatformManifest? get platformManifest =>
      _manifest?.platforms[currentPlatform];

  ManifestRelease? get latestRelease {
    final releases = platformManifest?.releases ?? const [];
    for (final release in releases) {
      if (release.channel == 'stable') return release;
    }
    return releases.isEmpty ? null : releases.first;
  }

  ReleaseArtifact? get latestArtifact {
    final artifacts = latestRelease?.artifacts ?? const [];
    final expectedType = switch (currentPlatform) {
      'windows' => 'exe',
      'macos' => 'zip',
      _ => null,
    };
    if (expectedType == null) return null;
    for (final artifact in artifacts) {
      if (artifact.type == expectedType) return artifact;
    }
    return null;
  }

  bool get hasOTAUpdate {
    final release = latestRelease;
    if (release == null || latestArtifact == null) return false;
    if (release.build != null) return release.build! > currentBuild;
    return _isNewerVersion(release.version, currentVersion);
  }

  bool get isForceUpdate {
    final minimumBuild = platformManifest?.minimumSupportedBuild;
    return hasOTAUpdate && minimumBuild != null && currentBuild < minimumBuild;
  }

  String? get latestVersion => latestRelease?.version;
  ManifestNotice? get currentNotice =>
      _pendingNotices.isEmpty ? null : _pendingNotices.first;
  bool get hasUnreadNotice => currentNotice != null;

  Future<void> loadManifest({bool forceRefresh = false}) async {
    if (_state == ManifestState.loading) return;
    _state = ManifestState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      LoggerService.info('📦 加载 Manifest v2...');
      final manifest = await _service.getManifest();
      if (manifest == null) {
        _state = ManifestState.error;
        _errorMessage = '获取 Manifest v2 失败';
      } else {
        _manifest = manifest;
        _pendingNotices = _visibleUnreadNotices(manifest.announcements);
        _state = ManifestState.loaded;
        LoggerService.info('✅ Manifest v2 加载成功: ${manifest.revision}');
        final release = latestRelease;
        if (release != null) {
          AnalyticsService.instance.trackOtaCheck(
            hasOTAUpdate ? 'update_available' : 'up_to_date',
            currentVersion,
            latestVersion: release.version,
          );
        } else {
          AnalyticsService.instance.trackOtaCheck('no_release', currentVersion);
        }
      }
    } catch (error) {
      _state = ManifestState.error;
      _errorMessage = '加载 Manifest v2 时发生错误: $error';
      LoggerService.error('❌ Manifest v2 加载异常', error: error);
    }
    notifyListeners();
  }

  Future<void> dismissCurrentNotice() async {
    final notice = currentNotice;
    if (notice == null) return;
    final dismissed =
        _prefs.getStringList(_dismissedNoticeIDsKey)?.toSet() ?? {};
    dismissed.add(notice.id);
    await _prefs.setStringList(
      _dismissedNoticeIDsKey,
      dismissed.toList()..sort(),
    );
    _pendingNotices = _pendingNotices.skip(1).toList(growable: false);
    notifyListeners();
  }

  Future<void> retry() => loadManifest(forceRefresh: true);

  List<ManifestNotice> _visibleUnreadNotices(List<ManifestNotice> notices) {
    final dismissed =
        _prefs.getStringList(_dismissedNoticeIDsKey)?.toSet() ?? {};
    final now = DateTime.now();
    return notices
        .where((notice) {
          final targetsPlatform =
              notice.platforms.contains('all') ||
              notice.platforms.contains(currentPlatform);
          final targetsApp = notice.surfaces.contains('app');
          final expiry = notice.expiresAt == null
              ? null
              : DateTime.tryParse(notice.expiresAt!);
          final active =
              notice.expiresAt == null ||
              (expiry != null && expiry.isAfter(now));
          return notice.id.isNotEmpty &&
              targetsPlatform &&
              targetsApp &&
              active &&
              !dismissed.contains(notice.id);
        })
        .toList(growable: false);
  }

  bool _isNewerVersion(String remote, String local) {
    try {
      final remoteParts = remote.split('.').map(int.parse).toList();
      final localParts = local.split('.').map(int.parse).toList();
      final length = remoteParts.length > localParts.length
          ? remoteParts.length
          : localParts.length;
      for (var index = 0; index < length; index++) {
        final remotePart = index < remoteParts.length ? remoteParts[index] : 0;
        final localPart = index < localParts.length ? localParts[index] : 0;
        if (remotePart != localPart) return remotePart > localPart;
      }
      return false;
    } catch (error) {
      LoggerService.error('❌ 版本号比较失败', error: error);
      return false;
    }
  }
}
