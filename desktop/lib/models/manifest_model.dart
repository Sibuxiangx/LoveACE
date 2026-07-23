import 'package:json_annotation/json_annotation.dart';

part 'manifest_model.g.dart';

@JsonSerializable()
class ManifestNotice {
  @JsonKey(defaultValue: '')
  final String id;
  @JsonKey(defaultValue: '')
  final String title;
  @JsonKey(defaultValue: '')
  final String content;
  @JsonKey(defaultValue: 'info')
  final String level;
  @JsonKey(defaultValue: <String>[])
  final List<String> platforms;
  @JsonKey(defaultValue: <String>[])
  final List<String> surfaces;
  @JsonKey(name: 'published_at', defaultValue: '')
  final String publishedAt;
  @JsonKey(name: 'expires_at')
  final String? expiresAt;
  @JsonKey(name: 'require_confirmation', defaultValue: false)
  final bool requireConfirmation;

  const ManifestNotice({
    required this.id,
    required this.title,
    required this.content,
    required this.level,
    required this.platforms,
    required this.surfaces,
    required this.publishedAt,
    this.expiresAt,
    required this.requireConfirmation,
  });

  factory ManifestNotice.fromJson(Map<String, dynamic> json) =>
      _$ManifestNoticeFromJson(json);

  Map<String, dynamic> toJson() => _$ManifestNoticeToJson(this);
}

@JsonSerializable()
class ArtifactChecksums {
  final String? sha256;
  final String? md5;

  const ArtifactChecksums({this.sha256, this.md5});

  factory ArtifactChecksums.fromJson(Map<String, dynamic> json) =>
      _$ArtifactChecksumsFromJson(json);

  Map<String, dynamic> toJson() => _$ArtifactChecksumsToJson(this);
}

@JsonSerializable()
class ReleaseArtifact {
  @JsonKey(defaultValue: '')
  final String type;
  @JsonKey(defaultValue: '')
  final String url;
  final String? arch;
  final int? size;
  final ArtifactChecksums checksums;

  const ReleaseArtifact({
    required this.type,
    required this.url,
    this.arch,
    this.size,
    required this.checksums,
  });

  factory ReleaseArtifact.fromJson(Map<String, dynamic> json) =>
      _$ReleaseArtifactFromJson(json);

  Map<String, dynamic> toJson() => _$ReleaseArtifactToJson(this);
}

@JsonSerializable()
class ManifestRelease {
  @JsonKey(defaultValue: '')
  final String id;
  @JsonKey(defaultValue: '')
  final String version;
  final int? build;
  @JsonKey(defaultValue: 'stable')
  final String channel;
  @JsonKey(name: 'published_at', defaultValue: '')
  final String publishedAt;
  @JsonKey(defaultValue: '')
  final String summary;
  @JsonKey(defaultValue: <String>[])
  final List<String> changelog;
  @JsonKey(defaultValue: <ReleaseArtifact>[])
  final List<ReleaseArtifact> artifacts;

  const ManifestRelease({
    required this.id,
    required this.version,
    this.build,
    required this.channel,
    required this.publishedAt,
    required this.summary,
    required this.changelog,
    required this.artifacts,
  });

  factory ManifestRelease.fromJson(Map<String, dynamic> json) =>
      _$ManifestReleaseFromJson(json);

  Map<String, dynamic> toJson() => _$ManifestReleaseToJson(this);
}

@JsonSerializable()
class PlatformManifest {
  @JsonKey(name: 'minimum_supported_build')
  final int? minimumSupportedBuild;
  @JsonKey(defaultValue: <ManifestRelease>[])
  final List<ManifestRelease> releases;

  const PlatformManifest({this.minimumSupportedBuild, required this.releases});

  factory PlatformManifest.fromJson(Map<String, dynamic> json) =>
      _$PlatformManifestFromJson(json);

  Map<String, dynamic> toJson() => _$PlatformManifestToJson(this);
}

@JsonSerializable()
class ManifestV2 {
  @JsonKey(name: 'schema_version', defaultValue: 0)
  final int schemaVersion;
  @JsonKey(defaultValue: '')
  final String revision;
  @JsonKey(name: 'generated_at', defaultValue: '')
  final String generatedAt;
  @JsonKey(defaultValue: <ManifestNotice>[])
  final List<ManifestNotice> announcements;
  @JsonKey(defaultValue: <String, PlatformManifest>{})
  final Map<String, PlatformManifest> platforms;

  const ManifestV2({
    required this.schemaVersion,
    required this.revision,
    required this.generatedAt,
    required this.announcements,
    required this.platforms,
  });

  factory ManifestV2.fromJson(Map<String, dynamic> json) =>
      _$ManifestV2FromJson(json);

  Map<String, dynamic> toJson() => _$ManifestV2ToJson(this);
}
