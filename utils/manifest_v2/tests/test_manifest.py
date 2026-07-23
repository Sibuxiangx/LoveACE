import json
import unittest

from cli import (
    LEGACY_MANIFEST_KEY,
    MANIFEST_V2_KEY,
    load_manifest_v2,
    save_manifest_outputs,
)
from manifest import (
    Announcement,
    ArtifactChecksums,
    ChangelogEntry,
    SemesterDataFile,
    LoveACEManifest,
    ManifestV2,
    OTA,
    PlatformManifest,
    PlatformRelease,
    Release,
    ReleaseArtifact,
    SemesterEntry,
    SemesterManifest,
)


def semester_data() -> SemesterDataFile:
    return SemesterDataFile(
        version=1,
        updated_at="2026-07-23T00:00:00+08:00",
        semesters=[
            SemesterEntry(
                code="2026-2027-1",
                name="2026-2027学年第一学期",
                start_date="2026-08-31",
                weeks=18,
            )
        ],
    )


class FakeClient:
    def __init__(self, objects=None):
        self.objects = objects or {}

    def get_json(self, key, *, missing_ok=False):
        value = self.objects.get(key)
        if value is None and not missing_ok:
            raise FileNotFoundError(key)
        return value

    def upload_content(self, content, key):
        self.objects[key] = json.loads(content)
        return f"https://release.loveace.top/{key}"


class ManifestTests(unittest.TestCase):
    def test_legacy_announcement_serializes_md5(self):
        announcement = Announcement(title="Title", content="Body")
        payload = json.loads(announcement.model_dump_json())
        self.assertEqual(payload["md5"], announcement.md5)

    def test_migration_rewrites_native_release_to_canonical_cdn(self):
        legacy = LoveACEManifest(
            ota=OTA(
                content="Update",
                changelog=[ChangelogEntry(version="1.2.3", changes="Fixed")],
                android=PlatformRelease(
                    version="1.2.3",
                    url=(
                        "https://release-oss.loveace.tech/loveace/releases/"
                        "android/1.2.3/app-release.apk"
                    ),
                    md5="abc",
                ),
            )
        )
        manifest = ManifestV2.from_legacy(legacy, semester_data())
        release = manifest.platforms["android"].releases[0]
        self.assertEqual(
            release.artifacts[0].url,
            (
                "https://release.loveace.top/loveace/releases/"
                "android/1.2.3/app-release.apk"
            ),
        )
        self.assertEqual(release.changelog, ["Fixed"])

    def test_v2_projects_platform_release_to_legacy(self):
        manifest = ManifestV2(
            semester=SemesterManifest.from_data_file(semester_data()),
            platforms={
                "android": PlatformManifest(
                    minimum_supported_build=10203,
                    releases=[
                        Release(
                            id="android-1.2.3-10203",
                            version="1.2.3",
                            build=10203,
                            published_at="2026-07-23T00:00:00Z",
                            summary="Update now",
                            changelog=["Fixed Android"],
                            artifacts=[
                                ReleaseArtifact(
                                    type="apk",
                                    arch="universal",
                                    url=(
                                        "https://release.loveace.top/loveace/releases/"
                                        "android/1.2.3/10203/app.apk"
                                    ),
                                    checksums=ArtifactChecksums(
                                        sha256="sha", md5="md5"
                                    ),
                                )
                            ],
                        )
                    ],
                )
            },
        )
        legacy = manifest.to_legacy_manifest()
        self.assertEqual(legacy.ota.android.version, "1.2.3")
        self.assertTrue(legacy.ota.android.force_ota)
        self.assertEqual(legacy.ota.android.md5, "md5")
        self.assertEqual(legacy.ota.changelog[0].version, "Android 1.2.3")

    def test_save_outputs_share_one_v2_snapshot(self):
        client = FakeClient()
        manifest = ManifestV2(
            semester=SemesterManifest.from_data_file(semester_data())
        )
        urls = save_manifest_outputs(client, manifest)
        self.assertEqual(set(urls), {"v2", "legacy_ota"})
        self.assertEqual(
            client.objects[MANIFEST_V2_KEY]["revision"], manifest.revision
        )
        self.assertIn("ota", client.objects[LEGACY_MANIFEST_KEY])

    def test_load_bootstraps_from_legacy(self):
        client = FakeClient(
            {
                LEGACY_MANIFEST_KEY: LoveACEManifest(
                    announcement=Announcement(title="Hello", content="World")
                ).model_dump(mode="json", exclude_none=True)
            }
        )
        manifest, migrated = load_manifest_v2(client)
        self.assertTrue(migrated)
        self.assertEqual(manifest.announcements[0].title, "Hello")


if __name__ == "__main__":
    unittest.main()
