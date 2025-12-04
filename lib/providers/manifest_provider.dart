import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';
import '../models/manifest_model.dart';
import '../services/manifest_service.dart';
import '../services/logger_service.dart';

enum ManifestState {
  initial,
  loading,
  loaded,
  error,
}

/// Manifest Provider
///
/// 管理应用公告和 OTA 更新信息的状态
class ManifestProvider extends ChangeNotifier {
  final ManifestService _service;
  final SharedPreferences _prefs;

  static const String _announcementMd5Key = 'announcement_md5_shown';

  ManifestState _state = ManifestState.initial;
  LoveACEManifest? _manifest;
  String? _errorMessage;

  ManifestState get state => _state;
  LoveACEManifest? get manifest => _manifest;
  String? get errorMessage => _errorMessage;

  /// 获取当前平台名称
  String get currentPlatform {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  /// 获取当前应用版本
  String get currentVersion => AppConstants.appVersion;

  /// 是否有新公告（未显示过）
  bool get hasNewAnnouncement {
    if (_manifest?.announcement == null) return false;
    final announcement = _manifest!.announcement!;
    final shownMd5 = _prefs.getString(_announcementMd5Key);
    return shownMd5 != announcement.md5;
  }

  /// 是否有 OTA 更新（针对当前平台）
  bool get hasOTAUpdate {
    if (_manifest?.ota == null) return false;
    final ota = _manifest!.ota!;
    
    // 检查是否有当前平台的发布
    final release = ota.getPlatformRelease(currentPlatform);
    if (release == null) return false;
    
    // 比较版本号（使用平台特定的版本号）
    return _isNewerVersion(release.version, currentVersion);
  }

  /// 是否为强制更新（使用平台特定的强制更新标志）
  bool get isForceUpdate {
    if (_manifest?.ota == null) return false;
    final release = _manifest!.ota!.getPlatformRelease(currentPlatform);
    if (release == null) return false;
    return release.forceOta && hasOTAUpdate;
  }

  /// 获取当前平台的最新版本号
  String? get latestVersion {
    if (_manifest?.ota == null) return null;
    final release = _manifest!.ota!.getPlatformRelease(currentPlatform);
    return release?.version;
  }

  /// 获取 OTA 信息
  OTA? get ota => _manifest?.ota;

  /// 获取公告信息
  Announcement? get announcement => _manifest?.announcement;

  ManifestProvider({
    required ManifestService service,
    required SharedPreferences prefs,
  })  : _service = service,
        _prefs = prefs;

  /// 加载 Manifest
  Future<void> loadManifest({bool forceRefresh = false}) async {
    if (_state == ManifestState.loading) return;

    _state = ManifestState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      LoggerService.info('📦 加载 Manifest...');

      final manifest = await _service.getManifest();

      if (manifest != null) {
        _manifest = manifest;
        _state = ManifestState.loaded;
        _errorMessage = null;
        LoggerService.info('✅ Manifest 加载成功');
        
        // 记录版本检查结果
        if (manifest.ota != null) {
          final platformRelease = manifest.ota!.getPlatformRelease(currentPlatform);
          if (platformRelease != null) {
            LoggerService.info('📱 当前版本: $currentVersion, 最新版本: ${platformRelease.version}');
            LoggerService.info('📱 当前平台: $currentPlatform');
            LoggerService.info('📱 有更新: $hasOTAUpdate, 强制更新: $isForceUpdate');
          } else {
            LoggerService.info('📱 当前平台 $currentPlatform 暂无发布');
          }
        }
      } else {
        _state = ManifestState.error;
        _errorMessage = '获取 Manifest 失败';
        LoggerService.error('❌ Manifest 加载失败');
      }
    } catch (e) {
      _state = ManifestState.error;
      _errorMessage = '加载 Manifest 时发生错误: $e';
      LoggerService.error('❌ Manifest 加载异常', error: e);
    }

    notifyListeners();
  }

  /// 标记公告为已显示
  Future<void> markAnnouncementAsShown() async {
    if (_manifest?.announcement == null) return;

    final md5 = _manifest!.announcement!.md5;
    await _prefs.setString(_announcementMd5Key, md5);
    LoggerService.info('✅ 公告已标记为已显示');
    notifyListeners();
  }

  /// 重试加载
  Future<void> retry() async {
    await loadManifest(forceRefresh: true);
  }

  /// 比较版本号，判断 newVersion 是否比 currentVersion 新
  /// 
  /// 版本号格式: major.minor.patch (例如 1.0.1)
  bool _isNewerVersion(String newVersion, String currentVersion) {
    try {
      final newParts = newVersion.split('.').map(int.parse).toList();
      final currentParts = currentVersion.split('.').map(int.parse).toList();

      // 补齐版本号长度
      while (newParts.length < 3) {
        newParts.add(0);
      }
      while (currentParts.length < 3) {
        currentParts.add(0);
      }

      // 比较 major
      if (newParts[0] > currentParts[0]) return true;
      if (newParts[0] < currentParts[0]) return false;

      // 比较 minor
      if (newParts[1] > currentParts[1]) return true;
      if (newParts[1] < currentParts[1]) return false;

      // 比较 patch
      if (newParts[2] > currentParts[2]) return true;

      return false;
    } catch (e) {
      LoggerService.error('❌ 版本号比较失败', error: e);
      return false;
    }
  }
}
