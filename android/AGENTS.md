# AGENTS.md

## Build and verification

- This machine does **not** have a usable Android build environment. Do not rely on local `./gradlew assemble*`; validate syntax/whitespace locally with `git diff --check`, then use GitHub Actions for real builds.
- CI/release workflow: `.github/workflows/build-apk.yml`. It is **manual only** (`workflow_dispatch`), installs JDK 17 + Android SDK 36, restores signing secrets, builds the release APK, uploads the artifact, then publishes it through `utils/manifest_v2` with `uv run python cli.py release ...`.
- Trigger Android release manually with inputs, for example:
  `gh workflow run build-apk.yml --ref main -f version=1.1.11 -f changelog="更新内容" -f content="发现新版本" -f force=false`.
- Check/watch/download CI artifacts:
  - `gh run list --workflow build-apk.yml --branch main --limit 5`
  - `gh run watch <run-id> --exit-status`
  - `gh run download <run-id> -n loveace-release-apk -D <dir>`
- Debug APKs are signed with the runner debug key and will not install over release builds. Release APKs are signed in GitHub Actions from repository secrets; do not commit keystores or signing passwords.

## Versioning and release

- Android version lives in `app/build.gradle.kts`. Keep `versionCode = major * 10000 + minor * 100 + patch` (for example `1.1.10 -> 10110`).
- Publishing is part of the manual GitHub Actions workflow after a successful release build. The workflow validates the requested version against Gradle, reads `versionCode`, then runs `cd utils/manifest_v2 && uv run python cli.py release --version <x.y.z> --build <versionCode> --platform android --file <release-apk> --content "..." --changelog "..."`.
- `utils/manifest_v2` reads S3/CDN credentials from environment variables in GitHub Actions secrets. For local one-off publishing it can still read `.env` (ignored). Do not print or commit credentials.
- The publish CLI uploads APKs to `loveace/releases/<platform>/<version>/<build>/...`, computes SHA-256 and compatibility MD5, updates canonical `loveace/manifest_v2.json`, and generates the legacy OTA projection; check with `uv run python cli.py status` from `utils/manifest_v2`.

## App wiring

- Single Android module: `:app`; package root is `tech.loveace.appv3`.
- Compose entrypoint is `MainActivity.kt` / `RibbonApp`. Type-safe routes are in `ui/navigation/AppNavigation.kt`.
- Portrait bottom-nav shell is `ui/screen/MainShell.kt`; landscape navigation is `ui/screen/landscape/LandscapeShell.kt`. User-facing features that belong in “More/教务服务” usually need both portrait and landscape entry points.
- Services are manually created in `AuthViewModel.initServices()` and cleared in `clearServices()`. New authenticated features normally add a `data/service/*Service`, `ui/viewmodel/*ViewModel`, screen(s), route, and an `AuthViewModel` service property.

## Network/session conventions

- Reuse `AUFEConnection` and its shared `HttpClient`/`SmartCookieJar`; do not implement a parallel login flow for school services.
- Login is two-stage: VPN EC login, then UAAP/CAS login. `AuthViewModel` wires session-expiry detection and auto-reconnect.
- `HttpClient` only supplies a default mobile UA when a request did not set `User-Agent`; service-specific UA headers are intentional.
- JWC endpoints use the VPN host `http://jwcxk2-aufe-edu-cn.vpn2.aufe.edu.cn:8118`; keep historical field spellings from upstream APIs, including `coureSequenceNumber`.

## UI conventions

- The app uses Compose Material3 Expressive (`androidx.compose.material3` alpha) and existing wavy indicators (`CircularWavyProgressIndicator`, `LinearWavyProgressIndicator`). Prefer these for loading/progress instead of introducing a different visual language.
- Keep changes surgical: many screens have separate portrait and landscape implementations; update both only when the feature is exposed in both modes.
