package tech.loveace.appv3.service

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class OtaServiceTest {
    @Test
    fun comparesNumericVersions() {
        assertTrue(OtaService.isNewerVersion("1.1.20", "1.1.19"))
        assertTrue(OtaService.isNewerVersion("1.10.0", "1.9.9"))
        assertFalse(OtaService.isNewerVersion("1.1.19", "1.1.19"))
        assertFalse(OtaService.isNewerVersion("1.1.18", "1.1.19"))
        assertFalse(OtaService.isNewerVersion("1.1.20-beta", "1.1.19"))
    }

    @Test
    fun parsesAndroidManifestV2() {
        val manifest = remoteManifestJson.decodeFromString<ManifestV2>(
            """
            {
              "schema_version": 2,
              "announcements": [{
                "id": "notice-1",
                "title": "公告",
                "content": "内容",
                "platforms": ["android"],
                "surfaces": ["app"]
              }],
              "platforms": {
                "android": {
                  "minimum_supported_build": 10120,
                  "releases": [{
                    "id": "android-1.1.20-10120",
                    "version": "1.1.20",
                    "build": 10120,
                    "changelog": ["支持新版远程配置"],
                    "artifacts": [{
                      "type": "apk",
                      "url": "https://release.loveace.top/app.apk",
                      "checksums": {"sha256": "abc"}
                    }]
                  }]
                }
              },
              "semester": {
                "schema_version": 1,
                "updated_at": "2026-07-23T00:00:00+08:00",
                "semesters": [{
                  "code": "2026-2027-1",
                  "name": "第一学期",
                  "start_date": "2026-08-31",
                  "weeks": 18
                }]
              }
            }
            """.trimIndent()
        )

        assertEquals(2, manifest.schemaVersion)
        assertEquals("notice-1", manifest.announcements.single().id)
        assertEquals(10120L, manifest.platforms["android"]?.minimumSupportedBuild)
        assertEquals("android-1.1.20-10120", manifest.platforms["android"]?.releases?.single()?.id)
        assertEquals("2026-2027-1", manifest.semester?.semesters?.single()?.code)
    }

    @Test
    fun calculatesSha256() {
        val file = File.createTempFile("loveace-ota", ".apk")
        try {
            file.writeText("LoveACE")
            assertEquals(
                "7cd27ba8951a5e9a4bc4058d476dedfc229a6bc29480ad7202f1a1ec37498a8f",
                OtaService.digestFile(file, "SHA-256"),
            )
        } finally {
            file.delete()
        }
    }
}
