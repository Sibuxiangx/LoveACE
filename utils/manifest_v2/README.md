# LoveACE Release Publisher

`manifest_v2.json` is the canonical release and semester document. The
publisher derives the legacy OTA document required by shipped clients.

## Public Objects

| Object | Purpose |
| --- | --- |
| `loveace/manifest_v2.json` | Canonical v2 manifest |
| `loveace/manifest.json` | Legacy OTA projection |
| `loveace/download.html` | Legacy download page |
| `loveace/download_page_v2.html` | Manifest v2 download page |

Native release URLs must use `https://release.loveace.top`. The publisher
rejects any other `CDN_BASE_URL` and stores immutable artifacts under:

```text
loveace/releases/<platform>/<version>/<build>/<filename>
```

Consumers read metadata from
`https://loveace.linota.cn/loveace/manifest_v2.json` first and fall back to
`https://release.loveace.top/loveace/manifest_v2.json`. This EdgeOne-first
policy applies only to metadata; native artifact URLs remain on the canonical
release host.

`semesters.json` in this directory is the authoring source for the nested v2
semester section. The existing Aliyun OSS semester endpoint remains online but
is no longer updated by this repository.

## Migration

The first `bootstrap` or release command reads the existing
`loveace/manifest.json` when `manifest_v2.json` does not exist. It imports the
current platform releases and the checked-in semester data, rewrites native
release origins to `release.loveace.top`, then publishes v2 and the legacy OTA
projection.

```bash
uv run python cli.py bootstrap
```

Do not edit a legacy projection directly. A later v2 publication will replace
it.

## Commands

```bash
# Native release
uv run python cli.py release \
  --platform android \
  --version 1.1.19 \
  --build 10119 \
  --file app-release.apk \
  --changelog "更新内容"

# TestFlight or web destination
uv run python cli.py web-release \
  --platform ios \
  --version 1.1 \
  --build 10 \
  --kind testflight \
  --url https://testflight.apple.com/join/example

# Global app announcement
uv run python cli.py announce \
  --id maintenance-202607 \
  --title "维护公告" \
  --content "维护内容" \
  --platform all \
  --surface app

# Platform download-page announcement
uv run python cli.py announce \
  --id android-install-202607 \
  --title "Android 安装提示" \
  --content "安装说明" \
  --platform android \
  --surface download

# Publish the checked-in semester data into manifest v2
uv run python cli.py sync-semesters
```

All GitHub Actions jobs that mutate a manifest use the
`loveace-manifest-publish` concurrency group. Local publication must not run in
parallel with those jobs.
