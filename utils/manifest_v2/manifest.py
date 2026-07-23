import hashlib
from datetime import datetime, timezone
from typing import Literal, Optional
from urllib.parse import urlsplit, urlunsplit
from uuid import uuid4

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    computed_field,
    field_validator,
    model_validator,
)


PLATFORMS = ("android", "ios", "windows", "macos", "linux")
NATIVE_ARTIFACT_TYPES = {"apk", "exe", "msix", "dmg", "zip"}
CANONICAL_RELEASE_HOST = "release.loveace.top"
RELEASE_PATH_PREFIX = "/loveace/releases/"


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


class Announcement(BaseModel):
    """Legacy v1 announcement."""

    title: str
    content: str
    confirm_require: bool = False

    @computed_field
    @property
    def md5(self) -> str:
        combined = f"{self.title}{self.content}"
        return hashlib.md5(combined.encode("utf-8")).hexdigest()

class ChangelogEntry(BaseModel):
    version: str
    changes: str


class PlatformRelease(BaseModel):
    version: str
    force_ota: bool = False
    url: str
    md5: Optional[str] = None
    type: str = "native"


class OTA(BaseModel):
    content: str = ""
    notice: Optional[str] = None
    changelog: list[ChangelogEntry] = Field(default_factory=list, max_length=10)
    android: Optional[PlatformRelease] = None
    ios: Optional[PlatformRelease] = None
    windows: Optional[PlatformRelease] = None
    macos: Optional[PlatformRelease] = None
    linux: Optional[PlatformRelease] = None


class LoveACEManifest(BaseModel):
    """Legacy OTA manifest consumed by already shipped clients."""

    model_config = ConfigDict(extra="ignore")

    announcement: Optional[Announcement] = None
    ota: Optional[OTA] = None

class SemesterEntry(BaseModel):
    code: str
    name: str
    start_date: str
    weeks: int = Field(default=18, gt=0, le=30)

    @field_validator("start_date")
    @classmethod
    def validate_start_date(cls, value: str) -> str:
        datetime.strptime(value, "%Y-%m-%d")
        return value


class SemesterDataFile(BaseModel):
    version: int = 1
    updated_at: str
    semesters: list[SemesterEntry]

    @model_validator(mode="after")
    def validate_unique_semesters(self):
        codes = [semester.code for semester in self.semesters]
        if len(codes) != len(set(codes)):
            raise ValueError("semester codes must be unique")
        return self


class SemesterManifest(BaseModel):
    schema_version: int = 1
    updated_at: str
    timezone: str = "Asia/Shanghai"
    semesters: list[SemesterEntry]

    @model_validator(mode="after")
    def validate_unique_semesters(self):
        codes = [semester.code for semester in self.semesters]
        if len(codes) != len(set(codes)):
            raise ValueError("semester codes must be unique")
        return self

    @classmethod
    def from_data_file(cls, data: SemesterDataFile) -> "SemesterManifest":
        return cls(
            schema_version=data.version,
            updated_at=data.updated_at,
            semesters=data.semesters,
        )


class ManifestAnnouncement(BaseModel):
    id: str
    title: str
    content: str
    level: Literal["info", "warning", "critical"] = "info"
    platforms: list[str] = Field(default_factory=lambda: ["all"])
    surfaces: list[Literal["app", "download"]] = Field(
        default_factory=lambda: ["app"]
    )
    published_at: str = Field(default_factory=utc_now)
    expires_at: Optional[str] = None
    require_confirmation: bool = False

    @field_validator("platforms")
    @classmethod
    def validate_platforms(cls, values: list[str]) -> list[str]:
        if not values:
            raise ValueError("announcement must target at least one platform")
        invalid = set(values) - set(PLATFORMS) - {"all"}
        if invalid:
            raise ValueError(f"unsupported announcement platforms: {sorted(invalid)}")
        return list(dict.fromkeys(values))


class ArtifactChecksums(BaseModel):
    sha256: Optional[str] = None
    md5: Optional[str] = None


class ReleaseArtifact(BaseModel):
    type: Literal["apk", "exe", "msix", "dmg", "zip", "testflight", "web"]
    url: str
    arch: Optional[str] = None
    size: Optional[int] = Field(default=None, ge=0)
    checksums: ArtifactChecksums = Field(default_factory=ArtifactChecksums)

    @field_validator("url")
    @classmethod
    def validate_url(cls, value: str) -> str:
        parsed = urlsplit(value)
        if parsed.scheme != "https" or not parsed.netloc:
            raise ValueError("artifact URL must be absolute HTTPS")
        return value

    @model_validator(mode="after")
    def validate_native_location(self):
        if self.type in NATIVE_ARTIFACT_TYPES:
            parsed = urlsplit(self.url)
            if parsed.netloc != CANONICAL_RELEASE_HOST:
                raise ValueError(
                    f"native artifacts must use {CANONICAL_RELEASE_HOST}"
                )
            if not parsed.path.startswith(RELEASE_PATH_PREFIX):
                raise ValueError(
                    f"native artifact path must start with {RELEASE_PATH_PREFIX}"
                )
        return self


class Release(BaseModel):
    id: str
    version: str
    build: Optional[int] = Field(default=None, ge=0)
    channel: str = "stable"
    published_at: str = Field(default_factory=utc_now)
    summary: str = ""
    changelog: list[str] = Field(default_factory=list)
    artifacts: list[ReleaseArtifact] = Field(min_length=1)


class PlatformManifest(BaseModel):
    minimum_supported_build: Optional[int] = Field(default=None, ge=0)
    releases: list[Release] = Field(default_factory=list, max_length=10)


class LegacyProjectionState(BaseModel):
    """Temporary v1-only data that cannot be assigned to a native platform."""

    changelog: list[ChangelogEntry] = Field(default_factory=list, max_length=10)


class ManifestV2(BaseModel):
    schema_version: Literal[2] = 2
    revision: str = Field(default_factory=lambda: uuid4().hex)
    generated_at: str = Field(default_factory=utc_now)
    announcements: list[ManifestAnnouncement] = Field(default_factory=list)
    platforms: dict[str, PlatformManifest] = Field(default_factory=dict)
    semester: SemesterManifest
    legacy_projection: LegacyProjectionState = Field(
        default_factory=LegacyProjectionState
    )

    @field_validator("platforms")
    @classmethod
    def validate_platform_keys(
        cls, value: dict[str, PlatformManifest]
    ) -> dict[str, PlatformManifest]:
        invalid = set(value) - set(PLATFORMS)
        if invalid:
            raise ValueError(f"unsupported platforms: {sorted(invalid)}")
        return value

    def touch(self) -> None:
        self.revision = uuid4().hex
        self.generated_at = utc_now()

    def to_legacy_manifest(self) -> LoveACEManifest:
        active_app_announcement = next(
            (
                item
                for item in self.announcements
                if "all" in item.platforms and "app" in item.surfaces
            ),
            None,
        )
        announcement = None
        if active_app_announcement:
            announcement = Announcement(
                title=active_app_announcement.title,
                content=active_app_announcement.content,
                confirm_require=active_app_announcement.require_confirmation,
            )

        notice_announcement = next(
            (
                item
                for item in self.announcements
                if "all" in item.platforms and "download" in item.surfaces
            ),
            None,
        )

        releases: list[tuple[str, Release]] = []
        ota = OTA(
            notice=notice_announcement.content if notice_announcement else None,
        )
        for platform in PLATFORMS:
            platform_manifest = self.platforms.get(platform)
            if not platform_manifest or not platform_manifest.releases:
                continue
            latest = platform_manifest.releases[0]
            releases.append((platform, latest))
            artifact = latest.artifacts[0]
            is_web = artifact.type in {"testflight", "web"}
            force_ota = (
                latest.build is not None
                and platform_manifest.minimum_supported_build == latest.build
            )
            setattr(
                ota,
                platform,
                PlatformRelease(
                    version=latest.version,
                    force_ota=force_ota,
                    url=artifact.url,
                    md5=artifact.checksums.md5,
                    type="web" if is_web else "native",
                ),
            )

        releases.sort(key=lambda item: item[1].published_at, reverse=True)
        if releases:
            ota.content = releases[0][1].summary

        changelog_entries: list[tuple[str, ChangelogEntry]] = []
        for platform, platform_manifest in self.platforms.items():
            for release in platform_manifest.releases:
                for change in release.changelog:
                    changelog_entries.append(
                        (
                            release.published_at,
                            ChangelogEntry(
                                version=f"{platform.capitalize()} {release.version}",
                                changes=change,
                            ),
                        )
                    )
        changelog_entries.sort(key=lambda item: item[0], reverse=True)
        generated_changelog = [entry for _, entry in changelog_entries]
        seen = {(entry.version, entry.changes) for entry in generated_changelog}
        for entry in self.legacy_projection.changelog:
            identity = (entry.version, entry.changes)
            if identity not in seen:
                generated_changelog.append(entry)
                seen.add(identity)
        ota.changelog = generated_changelog[:10]

        return LoveACEManifest(announcement=announcement, ota=ota)

    @classmethod
    def from_legacy(
        cls,
        manifest: LoveACEManifest,
        semester: SemesterDataFile,
    ) -> "ManifestV2":
        generated_at = utc_now()
        announcements: list[ManifestAnnouncement] = []
        if manifest.announcement:
            announcements.append(
                ManifestAnnouncement(
                    id=f"legacy-{manifest.announcement.md5}",
                    title=manifest.announcement.title,
                    content=manifest.announcement.content,
                    platforms=["all"],
                    surfaces=["app"],
                    require_confirmation=manifest.announcement.confirm_require,
                    published_at=generated_at,
                )
            )
        if manifest.ota and manifest.ota.notice:
            notice_hash = hashlib.sha256(
                manifest.ota.notice.encode("utf-8")
            ).hexdigest()[:16]
            announcements.append(
                ManifestAnnouncement(
                    id=f"legacy-notice-{notice_hash}",
                    title="下载提示",
                    content=manifest.ota.notice,
                    platforms=["all"],
                    surfaces=["download"],
                    published_at=generated_at,
                )
            )

        platforms: dict[str, PlatformManifest] = {}
        if manifest.ota:
            for platform in PLATFORMS:
                legacy_release = getattr(manifest.ota, platform, None)
                if not legacy_release:
                    continue
                artifact_type = (
                    "web"
                    if legacy_release.type == "web"
                    else _infer_artifact_type(legacy_release.url)
                )
                artifact_url = legacy_release.url
                if artifact_type in NATIVE_ARTIFACT_TYPES:
                    parsed = urlsplit(artifact_url)
                    if not parsed.path.startswith(RELEASE_PATH_PREFIX):
                        raise ValueError(
                            f"cannot migrate native release URL: {artifact_url}"
                        )
                    artifact_url = urlunsplit(
                        (
                            "https",
                            CANONICAL_RELEASE_HOST,
                            parsed.path,
                            parsed.query,
                            parsed.fragment,
                        )
                    )
                changes = [
                    entry.changes
                    for entry in manifest.ota.changelog
                    if entry.version == legacy_release.version
                    or entry.version.endswith(f" {legacy_release.version}")
                ]
                release = Release(
                    id=f"{platform}-{legacy_release.version}-legacy",
                    version=legacy_release.version,
                    published_at=generated_at,
                    summary=manifest.ota.content,
                    changelog=changes,
                    artifacts=[
                        ReleaseArtifact(
                            type=artifact_type,
                            url=artifact_url,
                            arch=None if artifact_type == "web" else "universal",
                            checksums=ArtifactChecksums(md5=legacy_release.md5),
                        )
                    ],
                )
                platforms[platform] = PlatformManifest(releases=[release])

        return cls(
            announcements=announcements,
            platforms=platforms,
            semester=SemesterManifest.from_data_file(semester),
            legacy_projection=LegacyProjectionState(
                changelog=manifest.ota.changelog if manifest.ota else []
            ),
        )


def _infer_artifact_type(url: str) -> str:
    suffix = urlsplit(url).path.rsplit(".", 1)[-1].lower()
    if suffix in NATIVE_ARTIFACT_TYPES:
        return suffix
    return "zip"
