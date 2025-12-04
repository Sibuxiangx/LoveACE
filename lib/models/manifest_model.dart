import 'package:json_annotation/json_annotation.dart';

part 'manifest_model.g.dart';

/// 公告模型
@JsonSerializable()
class Announcement {
  final String title;
  final String content;
  @JsonKey(name: 'confirm_require')
  final bool confirmRequire;
  final String md5;

  Announcement({
    required this.title,
    required this.content,
    required this.confirmRequire,
    required this.md5,
  });

  factory Announcement.fromJson(Map<String, dynamic> json) =>
      _$AnnouncementFromJson(json);

  Map<String, dynamic> toJson() => _$AnnouncementToJson(this);
}

/// 更新日志条目
@JsonSerializable()
class ChangelogEntry {
  final String version;
  final String changes;

  ChangelogEntry({
    required this.version,
    required this.changes,
  });

  factory ChangelogEntry.fromJson(Map<String, dynamic> json) =>
      _$ChangelogEntryFromJson(json);

  Map<String, dynamic> toJson() => _$ChangelogEntryToJson(this);
}

/// 平台发布信息
/// 
/// 每个平台独立管理版本号和强制更新标志
@JsonSerializable()
class PlatformRelease {
  final String version;
  @JsonKey(name: 'force_ota')
  final bool forceOta;
  final String url;
  final String md5;

  PlatformRelease({
    required this.version,
    required this.forceOta,
    required this.url,
    required this.md5,
  });

  factory PlatformRelease.fromJson(Map<String, dynamic> json) =>
      _$PlatformReleaseFromJson(json);

  Map<String, dynamic> toJson() => _$PlatformReleaseToJson(this);
}

/// OTA 更新模型
/// 
/// 每个平台独立管理版本号和强制更新标志
/// content 和 changelog 为所有平台共享的更新说明
@JsonSerializable()
class OTA {
  final String content;
  final List<ChangelogEntry> changelog;
  final PlatformRelease? android;
  final PlatformRelease? ios;
  final PlatformRelease? windows;
  final PlatformRelease? macos;
  final PlatformRelease? linux;

  OTA({
    required this.content,
    required this.changelog,
    this.android,
    this.ios,
    this.windows,
    this.macos,
    this.linux,
  });

  factory OTA.fromJson(Map<String, dynamic> json) => _$OTAFromJson(json);

  Map<String, dynamic> toJson() => _$OTAToJson(this);

  /// 获取当前平台的发布信息
  PlatformRelease? getPlatformRelease(String platform) {
    switch (platform.toLowerCase()) {
      case 'android':
        return android;
      case 'ios':
        return ios;
      case 'windows':
        return windows;
      case 'macos':
        return macos;
      case 'linux':
        return linux;
      default:
        return null;
    }
  }
}

/// Manifest 模型
@JsonSerializable()
class LoveACEManifest {
  final Announcement? announcement;
  final OTA? ota;

  LoveACEManifest({
    this.announcement,
    this.ota,
  });

  factory LoveACEManifest.fromJson(Map<String, dynamic> json) =>
      _$LoveACEManifestFromJson(json);

  Map<String, dynamic> toJson() => _$LoveACEManifestToJson(this);
}
