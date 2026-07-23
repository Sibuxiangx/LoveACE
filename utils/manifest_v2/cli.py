#!/usr/bin/env python3
"""LoveACE release, announcement, and remote manifest CLI."""

import hashlib
import json
from pathlib import Path
from typing import Optional
from urllib.parse import urlsplit

import typer
from rich.console import Console
from rich.panel import Panel
from rich.table import Table

from manifest import (
    ArtifactChecksums,
    SemesterDataFile,
    LoveACEManifest,
    ManifestAnnouncement,
    ManifestV2,
    PlatformManifest,
    Release,
    ReleaseArtifact,
    SemesterManifest,
    PLATFORMS,
    utc_now,
)
from s3_client import CANONICAL_CDN_BASE_URL, S3Client


app = typer.Typer(help="LoveACE 发布管理工具")
console = Console()

LEGACY_MANIFEST_KEY = "loveace/manifest.json"
MANIFEST_V2_KEY = "loveace/manifest_v2.json"
DOWNLOAD_PAGE_KEY = "loveace/download.html"
DOWNLOAD_PAGE_V2_KEY = "loveace/download_page_v2.html"
FAVICON_KEY = "loveace/favicon.png"
DOWNLOAD_ASSET_PREFIX = "loveace/assets"
LOCAL_SEMESTER_FILE = Path(__file__).parent / "semesters.json"
NATIVE_ARTIFACT_TYPES = {"apk", "exe", "msix", "dmg", "zip"}


def dump_json(model) -> str:
    return json.dumps(
        model.model_dump(mode="json", exclude_none=True),
        ensure_ascii=False,
        indent=2,
    )


def get_file_hashes(file_path: Path) -> tuple[str, str]:
    md5 = hashlib.md5()
    sha256 = hashlib.sha256()
    with file_path.open("rb") as file_handle:
        for chunk in iter(lambda: file_handle.read(1024 * 1024), b""):
            md5.update(chunk)
            sha256.update(chunk)
    return md5.hexdigest(), sha256.hexdigest()


def infer_artifact_type(file_path: Path) -> str:
    suffix = file_path.suffix.lower().lstrip(".")
    if suffix not in NATIVE_ARTIFACT_TYPES:
        raise typer.BadParameter(f"unsupported release artifact: {file_path.name}")
    return suffix


def read_local_semesters(path: Path = LOCAL_SEMESTER_FILE) -> SemesterDataFile:
    if not path.exists():
        raise FileNotFoundError(f"semester data not found: {path}")
    return SemesterDataFile.model_validate_json(path.read_text("utf-8"))


def load_manifest_v2(client: S3Client) -> tuple[ManifestV2, bool]:
    data = client.get_json(MANIFEST_V2_KEY, missing_ok=True)
    if data is not None:
        return ManifestV2.model_validate(data), False

    legacy_data = client.get_json(LEGACY_MANIFEST_KEY, missing_ok=True)
    legacy = (
        LoveACEManifest.model_validate(legacy_data)
        if legacy_data is not None
        else LoveACEManifest()
    )
    return ManifestV2.from_legacy(legacy, read_local_semesters()), True


def save_manifest_outputs(client: S3Client, manifest: ManifestV2) -> dict[str, str]:
    manifest.touch()
    legacy_manifest = manifest.to_legacy_manifest()
    urls = {
        "v2": client.upload_content(dump_json(manifest), MANIFEST_V2_KEY),
        "legacy_ota": client.upload_content(
            dump_json(legacy_manifest), LEGACY_MANIFEST_KEY
        ),
    }

    saved_v2 = ManifestV2.model_validate(client.get_json(MANIFEST_V2_KEY))
    if saved_v2.revision != manifest.revision:
        raise RuntimeError("manifest v2 verification failed: revision mismatch")
    LoveACEManifest.model_validate(client.get_json(LEGACY_MANIFEST_KEY))
    return urls


def ensure_platform(platform: str) -> None:
    if platform not in PLATFORMS:
        raise typer.BadParameter(
            f"unsupported platform {platform}; expected one of {', '.join(PLATFORMS)}"
        )


def add_release(manifest: ManifestV2, platform: str, release: Release) -> PlatformManifest:
    platform_manifest = manifest.platforms.get(platform, PlatformManifest())
    platform_manifest.releases = [
        item for item in platform_manifest.releases if item.id != release.id
    ]
    platform_manifest.releases.insert(0, release)
    platform_manifest.releases = platform_manifest.releases[:10]
    manifest.platforms[platform] = platform_manifest
    return platform_manifest


@app.command()
def bootstrap():
    """Create v2 and legacy projections without changing release data."""
    client = S3Client()
    manifest, migrated = load_manifest_v2(client)
    urls = save_manifest_outputs(client, manifest)
    action = "migrated from v1" if migrated else "republished"
    console.print(f"[green]Manifest outputs {action}[/]")
    for name, url in urls.items():
        console.print(f"[dim]{name}: {url}[/]")


@app.command()
def release(
    version: str = typer.Option(..., "--version", "-v", help="Display version"),
    build: int = typer.Option(..., "--build", "-b", min=0, help="Platform build number"),
    platform: str = typer.Option(..., "--platform", "-p"),
    file: Path = typer.Option(..., "--file", "-f", exists=True, dir_okay=False),
    force: bool = typer.Option(False, "--force"),
    minimum_supported_build: Optional[int] = typer.Option(
        None, "--minimum-supported-build", min=0
    ),
    content: str = typer.Option("", "--content", "-c"),
    changelog: str = typer.Option("", "--changelog"),
    arch: str = typer.Option("universal", "--arch"),
):
    """Publish one native platform release and all manifest projections."""
    ensure_platform(platform)
    if force and minimum_supported_build is not None:
        raise typer.BadParameter("use either --force or --minimum-supported-build")

    client = S3Client()
    manifest, _ = load_manifest_v2(client)
    md5, sha256 = get_file_hashes(file)
    artifact_type = infer_artifact_type(file)
    object_key = f"loveace/releases/{platform}/{version}/{build}/{file.name}"
    with console.status(f"[bold blue]Uploading {file.name}..."):
        download_url = client.upload_file(str(file), object_key)
    expected_prefix = f"{CANONICAL_CDN_BASE_URL}/loveace/releases/"
    if not download_url.startswith(expected_prefix):
        raise RuntimeError(f"release URL is not canonical: {download_url}")

    release_record = Release(
        id=f"{platform}-{version}-{build}",
        version=version,
        build=build,
        published_at=utc_now(),
        summary=content,
        changelog=[changelog] if changelog else [],
        artifacts=[
            ReleaseArtifact(
                type=artifact_type,
                arch=arch,
                url=download_url,
                size=file.stat().st_size,
                checksums=ArtifactChecksums(sha256=sha256, md5=md5),
            )
        ],
    )
    platform_manifest = add_release(manifest, platform, release_record)
    if force:
        platform_manifest.minimum_supported_build = build
    elif minimum_supported_build is not None:
        platform_manifest.minimum_supported_build = minimum_supported_build

    urls = save_manifest_outputs(client, manifest)
    console.print(
        Panel.fit(
            f"[bold green]Release published[/]\n\n"
            f"[cyan]Platform:[/] {platform}\n"
            f"[cyan]Version:[/] {version} ({build})\n"
            f"[cyan]SHA-256:[/] {sha256}\n"
            f"[cyan]URL:[/] {download_url}",
            title="Release",
        )
    )
    console.print(f"[dim]Manifest v2: {urls['v2']}[/]")


@app.command()
def web_release(
    version: str = typer.Option(..., "--version", "-v"),
    platform: str = typer.Option(..., "--platform", "-p"),
    url: str = typer.Option(..., "--url", "-u"),
    build: Optional[int] = typer.Option(None, "--build", "-b", min=0),
    kind: str = typer.Option("web", "--kind", help="web or testflight"),
    changelog: str = typer.Option("", "--changelog"),
    content: str = typer.Option("", "--content"),
):
    """Publish a web or TestFlight platform release."""
    ensure_platform(platform)
    if kind not in {"web", "testflight"}:
        raise typer.BadParameter("--kind must be web or testflight")
    parsed = urlsplit(url)
    if parsed.scheme != "https" or not parsed.netloc:
        raise typer.BadParameter("--url must be absolute HTTPS")

    client = S3Client()
    manifest, _ = load_manifest_v2(client)
    release_id = f"{platform}-{version}-{build if build is not None else 'web'}"
    add_release(
        manifest,
        platform,
        Release(
            id=release_id,
            version=version,
            build=build,
            published_at=utc_now(),
            summary=content,
            changelog=[changelog] if changelog else [],
            artifacts=[ReleaseArtifact(type=kind, url=url)],
        ),
    )
    urls = save_manifest_outputs(client, manifest)
    console.print(f"[green]{platform} {kind} release published[/]")
    console.print(f"[dim]Manifest v2: {urls['v2']}[/]")


@app.command()
def announce(
    title: str = typer.Option(..., "--title", "-t"),
    content: str = typer.Option(..., "--content", "-c"),
    announcement_id: Optional[str] = typer.Option(None, "--id"),
    platform: list[str] = typer.Option(["all"], "--platform"),
    surface: list[str] = typer.Option(["app"], "--surface"),
    level: str = typer.Option("info", "--level"),
    confirm_require: bool = typer.Option(False, "--confirm"),
):
    """Publish or replace a scoped v2 announcement."""
    if level not in {"info", "warning", "critical"}:
        raise typer.BadParameter("--level must be info, warning, or critical")
    invalid_surfaces = set(surface) - {"app", "download"}
    if invalid_surfaces:
        raise typer.BadParameter(f"unsupported surfaces: {sorted(invalid_surfaces)}")
    for item in platform:
        if item != "all":
            ensure_platform(item)

    if not announcement_id:
        digest = hashlib.sha256(f"{title}\0{content}".encode("utf-8")).hexdigest()
        announcement_id = f"announcement-{digest[:16]}"

    client = S3Client()
    manifest, _ = load_manifest_v2(client)
    announcement = ManifestAnnouncement(
        id=announcement_id,
        title=title,
        content=content,
        level=level,
        platforms=platform,
        surfaces=surface,
        require_confirmation=confirm_require,
        published_at=utc_now(),
    )
    manifest.announcements = [
        item for item in manifest.announcements if item.id != announcement_id
    ]
    manifest.announcements.insert(0, announcement)
    save_manifest_outputs(client, manifest)
    console.print(f"[green]Announcement published: {announcement_id}[/]")


@app.command()
def clear_announce(
    announcement_id: Optional[str] = typer.Option(None, "--id"),
):
    """Remove one announcement, or all app announcements when ID is omitted."""
    client = S3Client()
    manifest, _ = load_manifest_v2(client)
    if announcement_id:
        manifest.announcements = [
            item for item in manifest.announcements if item.id != announcement_id
        ]
    else:
        manifest.announcements = [
            item for item in manifest.announcements if "app" not in item.surfaces
        ]
    save_manifest_outputs(client, manifest)
    console.print("[green]Announcement cleared[/]")


@app.command()
def notice(content: str = typer.Option(..., "--content", "-c")):
    """Set the global download-page notice."""
    client = S3Client()
    manifest, _ = load_manifest_v2(client)
    manifest.announcements = [
        item for item in manifest.announcements if item.id != "download-notice"
    ]
    manifest.announcements.insert(
        0,
        ManifestAnnouncement(
            id="download-notice",
            title="下载提示",
            content=content,
            level="warning",
            platforms=["all"],
            surfaces=["download"],
        ),
    )
    save_manifest_outputs(client, manifest)
    console.print("[green]Download notice published[/]")


@app.command()
def clear_notice():
    """Clear the global download-page notice."""
    client = S3Client()
    manifest, _ = load_manifest_v2(client)
    manifest.announcements = [
        item
        for item in manifest.announcements
        if item.id != "download-notice" and "download" not in item.surfaces
    ]
    save_manifest_outputs(client, manifest)
    console.print("[green]Download notice cleared[/]")


@app.command("sync-semesters")
def sync_semesters(
    file: Path = typer.Option(
        LOCAL_SEMESTER_FILE, "--file", "-f", exists=True, dir_okay=False
    ),
):
    """Update semester data in the canonical v2 manifest."""
    semester_data = SemesterDataFile.model_validate_json(file.read_text("utf-8"))
    client = S3Client()
    manifest, _ = load_manifest_v2(client)
    manifest.semester = SemesterManifest.from_data_file(semester_data)
    urls = save_manifest_outputs(client, manifest)
    console.print(f"[green]Semester data published: {manifest.revision}[/]")
    console.print(f"[dim]Manifest v2: {urls['v2']}[/]")


@app.command()
def set_force(
    platform: str = typer.Option(..., "--platform", "-p"),
    force: bool = typer.Option(..., "--force", "-f"),
):
    """Set the legacy-compatible force policy for the latest platform build."""
    ensure_platform(platform)
    client = S3Client()
    manifest, _ = load_manifest_v2(client)
    platform_manifest = manifest.platforms.get(platform)
    if not platform_manifest or not platform_manifest.releases:
        raise typer.BadParameter(f"platform has no release: {platform}")
    latest = platform_manifest.releases[0]
    if force and latest.build is None:
        raise typer.BadParameter("migrated release has no build number")
    platform_manifest.minimum_supported_build = latest.build if force else None
    save_manifest_outputs(client, manifest)
    console.print(f"[green]{platform} force policy updated[/]")


@app.command()
def status():
    """Display the canonical v2 manifest status."""
    client = S3Client()
    manifest, migrated = load_manifest_v2(client)
    if migrated:
        console.print("[yellow]manifest_v2.json does not exist; showing v1 migration preview[/]")
    console.print(
        Panel.fit(
            f"[cyan]Schema:[/] {manifest.schema_version}\n"
            f"[cyan]Revision:[/] {manifest.revision}\n"
            f"[cyan]Generated:[/] {manifest.generated_at}\n"
            f"[cyan]Announcements:[/] {len(manifest.announcements)}\n"
            f"[cyan]Semesters:[/] {len(manifest.semester.semesters)}",
            title="Manifest v2",
        )
    )
    table = Table(title="Latest releases")
    table.add_column("Platform")
    table.add_column("Version")
    table.add_column("Build")
    table.add_column("Artifact")
    table.add_column("Minimum build")
    for platform in PLATFORMS:
        platform_manifest = manifest.platforms.get(platform)
        if not platform_manifest or not platform_manifest.releases:
            continue
        latest = platform_manifest.releases[0]
        table.add_row(
            platform,
            latest.version,
            str(latest.build) if latest.build is not None else "legacy",
            latest.artifacts[0].type,
            str(platform_manifest.minimum_supported_build or "-"),
        )
    console.print(table)


@app.command()
def deploy_page():
    """Deploy both download pages and the shared favicon."""
    client = S3Client()
    base_path = Path(__file__).parent
    assets = [
        (base_path / "download.html", DOWNLOAD_PAGE_KEY),
        (base_path / "download_page_v2.html", DOWNLOAD_PAGE_V2_KEY),
        (base_path / "favicon.png", FAVICON_KEY),
        (
            base_path / "assets" / "download-background-1600.webp",
            f"{DOWNLOAD_ASSET_PREFIX}/download-background-1600.webp",
        ),
        (
            base_path / "assets" / "download-background-900.webp",
            f"{DOWNLOAD_ASSET_PREFIX}/download-background-900.webp",
        ),
    ]
    for local_path, object_key in assets:
        if not local_path.exists():
            raise FileNotFoundError(f"page asset not found: {local_path}")
        url = client.upload_file(str(local_path), object_key)
        console.print(f"[green]Published {local_path.name}[/] [dim]{url}[/]")


if __name__ == "__main__":
    app()
