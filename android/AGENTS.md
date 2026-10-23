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
- `build-apk.yml` supports `dry_run=true`: builds and uploads the APK artifact but skips the `publish` job entirely. Use it to validate compilation before a real release.
- `setup-android@v3` must pin `packages: platform-tools` (the workflow does): the default value still references the retired `tools` package, which fails on runners with cmdline-tools 16+. GitHub also migrates `ubuntu-latest` between major OS versions; pin `ubuntu-24.04` if a runner image change breaks setup steps.
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
- Forced password change interception: CAS may 302 to `/mng/acp/completeInfo/password` after the TGT is issued (password is correct). `AUFEConnection.performUaapLogin` maps this to `UAAPLoginStatus(failPasswordChangeRequired)`; treat it as a non-error state — never clear credentials, never count it as a login failure, never auto-retry (reconnect() records it in `lastUaapPasswordChangeRequired` and `AuthViewModel` stops reconnecting).
- Captcha (EC gateway): when the auth page has `<RndImg>1</RndImg>`, or `login_psw.csp` answers 20041, the password is not submitted. `AUFEConnection.ecLogin(captchaCode)` returns `failCaptchaRequired` with `captchaImage` (GET `/por/rand_code.csp` with `Cookie: TWFID=<same auth page>`). The pending auth context (TWFID/CSRF/RSA) is in memory, single-use, valid 180 s, and reused by the code POST. `failCaptchaInvalid` (20023) counts as a failure and triggers a fresh challenge. Never log the code, the image, or the context.
- Login throttle: `AuthViewModel` counts `failInvalidCredentials` and `failCaptchaInvalid`. Cooldown ladder is 0 / 30 s / 120 s / 600 s (`loginCooldownMillis`), stored in SharedPreferences `login_throttle` (`failures_<userId>`, `cooldown_until_<userId>`) and cleared on success. Network errors and captcha prompts do not count.
- The captcha-waiting state uses `AuthState.Initial`, not `Error` or `Unauthenticated`: `MainActivity` navigates on those states and would reset the typed input. Auto-reconnect and session restore that need a captcha keep saved credentials and show "学校要求输入验证码，请重新登录".
- `HttpClient` only supplies a default mobile UA when a request did not set `User-Agent`; service-specific UA headers are intentional.
- JWC endpoints use the VPN host `http://jwcxk2-aufe-edu-cn.vpn2.aufe.edu.cn:8118`; keep historical field spellings from upstream APIs, including `coureSequenceNumber`.
- Auto teacher evaluation (`TeacherEvaluationService`/`TeacherEvaluationViewModel`) mirrors iOS/desktop behavior: first-visit protection wait (`TeacherEvaluationIndexProtection`, infoTime+5s), one immediate retry with a refreshed index token, verify-before-fail fallback, and one post-batch compensation round. Keep the three platforms consistent when touching it.

## Remote config

- `service/RemoteManifestService.kt` fetches `loveace/manifest_v2.json` (EdgeOne `loveace.linota.cn` first, `release.loveace.top` fallback) with `ignoreUnknownKeys`; unknown top-level fields are safe to add.
- OTA/update dialogs and announcements flow through `OtaService`/`OtaViewModel` (checked silently at app launch, before login).
- `prelogin_notice` is the pre-login banner rendered by `ui/screen/PreloginNoticeCard.kt` inside both login screens; fetch failures must stay silent and never block login. Publish/clear it via the `deploy-release-metadata.yml` workflow (`publish-prelogin` / `clear-prelogin`).

## UI conventions

- The app uses Compose Material3 Expressive (`androidx.compose.material3` alpha) and existing wavy indicators (`CircularWavyProgressIndicator`, `LinearWavyProgressIndicator`). Prefer these for loading/progress instead of introducing a different visual language.
- Keep changes surgical: many screens have separate portrait and landscape implementations; update both only when the feature is exposed in both modes.
