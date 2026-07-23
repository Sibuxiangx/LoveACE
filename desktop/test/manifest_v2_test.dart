import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loveace/models/manifest_model.dart';
import 'package:loveace/services/desktop_update_service.dart';

void main() {
  test('decodes desktop release and app notice from manifest v2', () {
    final manifest = ManifestV2.fromJson(
      jsonDecode('''
        {
          "schema_version": 2,
          "revision": "revision-1",
          "generated_at": "2026-07-23T00:00:00Z",
          "announcements": [{
            "id": "desktop-notice",
            "title": "公告",
            "content": "内容",
            "level": "warning",
            "platforms": ["macos", "windows"],
            "surfaces": ["app"],
            "published_at": "2026-07-23T00:00:00Z",
            "require_confirmation": true
          }],
          "platforms": {
            "macos": {
              "minimum_supported_build": 24,
              "releases": [{
                "id": "macos-1.1.13-24",
                "version": "1.1.13",
                "build": 24,
                "channel": "stable",
                "published_at": "2026-07-23T00:00:00Z",
                "summary": "更新说明",
                "changelog": ["支持 manifest v2"],
                "artifacts": [{
                  "type": "zip",
                  "url": "https://release.loveace.top/loveace/releases/macos/1.1.13/24/loveace-1.1.13.zip",
                  "arch": "universal",
                  "size": 1024,
                  "checksums": {"sha256": "abc", "md5": "def"}
                }]
              }]
            }
          }
        }
      ''')
          as Map<String, dynamic>,
    );

    expect(manifest.schemaVersion, 2);
    expect(manifest.announcements.single.id, 'desktop-notice');
    expect(manifest.announcements.single.requireConfirmation, isTrue);

    final platform = manifest.platforms['macos']!;
    expect(platform.minimumSupportedBuild, 24);
    expect(platform.releases.single.build, 24);
    expect(platform.releases.single.artifacts.single.type, 'zip');
    expect(
      platform.releases.single.artifacts.single.url,
      startsWith('https://release.loveace.top/loveace/releases/'),
    );
    expect(platform.releases.single.artifacts.single.checksums.sha256, 'abc');
  });

  test('verifies a downloaded installer with SHA-256', () async {
    final file = File('${Directory.systemTemp.path}/loveace-update-test.exe');
    await file.writeAsString('LoveACE');
    try {
      await DesktopUpdateService().verifyInstaller(
        file,
        const ArtifactChecksums(
          sha256:
              '7cd27ba8951a5e9a4bc4058d476dedfc229a6bc29480ad7202f1a1ec37498a8f',
        ),
      );
    } finally {
      if (await file.exists()) await file.delete();
    }
  });
}
