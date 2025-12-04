// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'manifest_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Announcement _$AnnouncementFromJson(Map<String, dynamic> json) => Announcement(
  title: json['title'] as String,
  content: json['content'] as String,
  confirmRequire: json['confirm_require'] as bool,
  md5: json['md5'] as String,
);

Map<String, dynamic> _$AnnouncementToJson(Announcement instance) =>
    <String, dynamic>{
      'title': instance.title,
      'content': instance.content,
      'confirm_require': instance.confirmRequire,
      'md5': instance.md5,
    };

ChangelogEntry _$ChangelogEntryFromJson(Map<String, dynamic> json) =>
    ChangelogEntry(
      version: json['version'] as String,
      changes: json['changes'] as String,
    );

Map<String, dynamic> _$ChangelogEntryToJson(ChangelogEntry instance) =>
    <String, dynamic>{'version': instance.version, 'changes': instance.changes};

PlatformRelease _$PlatformReleaseFromJson(Map<String, dynamic> json) =>
    PlatformRelease(
      version: json['version'] as String,
      forceOta: json['force_ota'] as bool,
      url: json['url'] as String,
      md5: json['md5'] as String,
    );

Map<String, dynamic> _$PlatformReleaseToJson(PlatformRelease instance) =>
    <String, dynamic>{
      'version': instance.version,
      'force_ota': instance.forceOta,
      'url': instance.url,
      'md5': instance.md5,
    };

OTA _$OTAFromJson(Map<String, dynamic> json) => OTA(
  content: json['content'] as String,
  changelog: (json['changelog'] as List<dynamic>)
      .map((e) => ChangelogEntry.fromJson(e as Map<String, dynamic>))
      .toList(),
  android: json['android'] == null
      ? null
      : PlatformRelease.fromJson(json['android'] as Map<String, dynamic>),
  ios: json['ios'] == null
      ? null
      : PlatformRelease.fromJson(json['ios'] as Map<String, dynamic>),
  windows: json['windows'] == null
      ? null
      : PlatformRelease.fromJson(json['windows'] as Map<String, dynamic>),
  macos: json['macos'] == null
      ? null
      : PlatformRelease.fromJson(json['macos'] as Map<String, dynamic>),
  linux: json['linux'] == null
      ? null
      : PlatformRelease.fromJson(json['linux'] as Map<String, dynamic>),
);

Map<String, dynamic> _$OTAToJson(OTA instance) => <String, dynamic>{
  'content': instance.content,
  'changelog': instance.changelog,
  'android': instance.android,
  'ios': instance.ios,
  'windows': instance.windows,
  'macos': instance.macos,
  'linux': instance.linux,
};

LoveACEManifest _$LoveACEManifestFromJson(Map<String, dynamic> json) =>
    LoveACEManifest(
      announcement: json['announcement'] == null
          ? null
          : Announcement.fromJson(json['announcement'] as Map<String, dynamic>),
      ota: json['ota'] == null
          ? null
          : OTA.fromJson(json['ota'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$LoveACEManifestToJson(LoveACEManifest instance) =>
    <String, dynamic>{
      'announcement': instance.announcement,
      'ota': instance.ota,
    };
