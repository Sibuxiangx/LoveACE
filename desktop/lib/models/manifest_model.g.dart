// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'manifest_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ManifestNotice _$ManifestNoticeFromJson(
  Map<String, dynamic> json,
) => ManifestNotice(
  id: json['id'] as String? ?? '',
  title: json['title'] as String? ?? '',
  content: json['content'] as String? ?? '',
  level: json['level'] as String? ?? 'info',
  platforms:
      (json['platforms'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      [],
  surfaces:
      (json['surfaces'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      [],
  publishedAt: json['published_at'] as String? ?? '',
  expiresAt: json['expires_at'] as String?,
  requireConfirmation: json['require_confirmation'] as bool? ?? false,
);

Map<String, dynamic> _$ManifestNoticeToJson(ManifestNotice instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'content': instance.content,
      'level': instance.level,
      'platforms': instance.platforms,
      'surfaces': instance.surfaces,
      'published_at': instance.publishedAt,
      'expires_at': instance.expiresAt,
      'require_confirmation': instance.requireConfirmation,
    };

ArtifactChecksums _$ArtifactChecksumsFromJson(Map<String, dynamic> json) =>
    ArtifactChecksums(
      sha256: json['sha256'] as String?,
      md5: json['md5'] as String?,
    );

Map<String, dynamic> _$ArtifactChecksumsToJson(ArtifactChecksums instance) =>
    <String, dynamic>{'sha256': instance.sha256, 'md5': instance.md5};

ReleaseArtifact _$ReleaseArtifactFromJson(Map<String, dynamic> json) =>
    ReleaseArtifact(
      type: json['type'] as String? ?? '',
      url: json['url'] as String? ?? '',
      arch: json['arch'] as String?,
      size: (json['size'] as num?)?.toInt(),
      checksums: ArtifactChecksums.fromJson(
        json['checksums'] as Map<String, dynamic>,
      ),
    );

Map<String, dynamic> _$ReleaseArtifactToJson(ReleaseArtifact instance) =>
    <String, dynamic>{
      'type': instance.type,
      'url': instance.url,
      'arch': instance.arch,
      'size': instance.size,
      'checksums': instance.checksums,
    };

ManifestRelease _$ManifestReleaseFromJson(Map<String, dynamic> json) =>
    ManifestRelease(
      id: json['id'] as String? ?? '',
      version: json['version'] as String? ?? '',
      build: (json['build'] as num?)?.toInt(),
      channel: json['channel'] as String? ?? 'stable',
      publishedAt: json['published_at'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      changelog:
          (json['changelog'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      artifacts:
          (json['artifacts'] as List<dynamic>?)
              ?.map((e) => ReleaseArtifact.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );

Map<String, dynamic> _$ManifestReleaseToJson(ManifestRelease instance) =>
    <String, dynamic>{
      'id': instance.id,
      'version': instance.version,
      'build': instance.build,
      'channel': instance.channel,
      'published_at': instance.publishedAt,
      'summary': instance.summary,
      'changelog': instance.changelog,
      'artifacts': instance.artifacts,
    };

PlatformManifest _$PlatformManifestFromJson(Map<String, dynamic> json) =>
    PlatformManifest(
      minimumSupportedBuild: (json['minimum_supported_build'] as num?)?.toInt(),
      releases:
          (json['releases'] as List<dynamic>?)
              ?.map((e) => ManifestRelease.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );

Map<String, dynamic> _$PlatformManifestToJson(PlatformManifest instance) =>
    <String, dynamic>{
      'minimum_supported_build': instance.minimumSupportedBuild,
      'releases': instance.releases,
    };

ManifestV2 _$ManifestV2FromJson(Map<String, dynamic> json) => ManifestV2(
  schemaVersion: (json['schema_version'] as num?)?.toInt() ?? 0,
  revision: json['revision'] as String? ?? '',
  generatedAt: json['generated_at'] as String? ?? '',
  announcements:
      (json['announcements'] as List<dynamic>?)
          ?.map((e) => ManifestNotice.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [],
  platforms:
      (json['platforms'] as Map<String, dynamic>?)?.map(
        (k, e) =>
            MapEntry(k, PlatformManifest.fromJson(e as Map<String, dynamic>)),
      ) ??
      {},
);

Map<String, dynamic> _$ManifestV2ToJson(ManifestV2 instance) =>
    <String, dynamic>{
      'schema_version': instance.schemaVersion,
      'revision': instance.revision,
      'generated_at': instance.generatedAt,
      'announcements': instance.announcements,
      'platforms': instance.platforms,
    };
