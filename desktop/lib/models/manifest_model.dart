import 'package:json_annotation/json_annotation.dart';

part 'manifest_model.g.dart';

/// 公告模型
@JsonSerializable()
class Announcement {
  @JsonKey(defaultValue: '')
  final String title;
  @JsonKey(defaultValue: '')
  final String content;
  @JsonKey(name: 'confirm_require', defaultValue: false)
  final bool confirmRequire;
  @JsonKey(defaultValue: '')
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
  @JsonKey(defaultValue: '')
  final String version;
  @JsonKey(defaultValue: '')
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
  @JsonKey(defaultValue: '')
  final String version;
  @JsonKey(name: 'force_ota', defaultValue: false)
  final bool forceOta;
  @JsonKey(defaultValue: '')
  final String url;
  @JsonKey(defaultValue: '')
  final String md5;
  @JsonKey(defaultValue: 'native')
  final String type;

  PlatformRelease({
    required this.version,
    required this.forceOta,
    required this.url,
    required this.md5,
    this.type = 'native',
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
  @JsonKey(defaultValue: '')
  final String content;
  @JsonKey(defaultValue: '')
  final String notice;
  @JsonKey(defaultValue: <ChangelogEntry>[])
  final List<ChangelogEntry> changelog;
  final PlatformRelease? android;
  final PlatformRelease? ios;
  final PlatformRelease? windows;
  final PlatformRelease? macos;
  final PlatformRelease? linux;

  OTA({
    required this.content,
    this.notice = '',
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
