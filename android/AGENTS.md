# AGENTS.md

## Build and verification

- This machine does **not** have a usable Android build environment. Do not rely on local `./gradlew assemble*`; validate syntax/whitespace locally with `git diff --check`, then use GitHub Actions for real builds.
- CI/release workflow: `.github/workflows/build-apk.yml`. It is **manual only** (`workflow_dispatch`), installs JDK 17 + Android SDK 36, restores signing secrets, builds the release APK, uploads the artifact, then publishes it through `utils/manifest_v2` with `uv run python cli.py release ...`.
- Trigger Android release manually with inputs, for example:
  `gh workflow run build-apk.yml --ref main -f version=1.1.11 -f changelog="更新内容" -f content="发现新版本" -f force=false`.
- Check/watch/download CI artifacts:
  - `gh run list --workflow build-apk.yml --branch main --limit 5`
  - `gh run watch <run-id> --exit-status`
  - `gh run download <run-id> -p 'LoveACE-*' -D <dir>`
- `build-apk.yml` supports `dry_run=true`: builds and uploads the APK artifact but skips the `publish` job entirely. Use it to validate compilation before a real release.
- APK/artifact name: `LoveACE-<version>-<build>-<sha7>-<yyyymmdd-HHMM>[-dryrun]` (Asia/Shanghai time). The build job renames `app-release.apk` before upload. The publish job restores `app-release.apk` before calling the CLI, so the S3 object key and release URL stay the same.
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
- Landscape nav items are mapped by array index in `LandscapeShell`'s `when (selectedIndex)`. Inserting or removing an item means shifting every index after it in the same edit (for example “开课查询” is index 5, “空闲教室” is 6, “我的” is 14).
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
- 开课查询（`CourseScheduleService.queryPage` + `CourseScheduleViewModel`，`ui/screen/CourseSchedule*.kt`）与 iOS 同一结构：右上角“筛选”打开条件 sheet（`CourseFilterSheet`），草稿在 sheet 里编辑，点“查询”才生效（`CourseScheduleUiState.applied`）；空状态引导点右上角。结果是分页列表，`courseInfo` 的 `PAGE_SIZE = 20`，接近末尾才加载下一页，不要一次拉取整个学期。学期列表与下拉选项来自同一个 `courseSchdule/index` 页面；页面没有某个维度的 `select` 时该下拉隐藏。记录按 `courseRecordKey` 跨页去重。横屏与竖屏共用 `CourseScheduleScaffold`。
- 空闲教室（`FreeClassroomService` + `FreeClassroomViewModel`，`ui/screen/FreeClassroom*.kt`）与 iOS 同一流程：时段（教学周、星期、节次多选）→ 范围（可不选）→ 查询。查询先取所选时段的空闲教室 `freeClassroomQuery/search`：未选校区时西校（2）、东校（1）各查一次，`weeks` 与 `wSection`（`weekday/section`，逗号分隔）必须非空，空值结果不可靠；再用 `classroomCurriculum/{campus}/{building}/classroomJson` 枚举范围内每栋楼的全部教室（不要用无条件查询，它会漏掉通慧楼等教学楼），按楼缓存在 VM 中，最多 4 栋并发。结果直接按楼、楼层展示全部教室并标出空闲或占用，没有楼详情页。占用来自详情页隐藏域 `wsSection`（`weekday_week_section`）。停用规则：教学楼备注或名称含“停用”的楼默认隐藏；房间名含“停用”的教室始终显示并带标记；状态码 `02` 或 `03` 的教室默认隐藏，打开“显示停用教室”后显示并带标记；名称含“虚拟”或座位数超过 1000 的记录不是实体教室，直接剔除；同一楼宇、同一房号的多行合并为一间。楼层为推测：三位数取首位，四位数取前两位，超过 12 层归入“其他”。切换“显示停用教室”时已有结果会自动重查。
- 空闲教室横屏与竖屏共用 `freeClassroomControlItems` / `freeClassroomResultItems`（`ui/screen/FreeClassroomScreen.kt`）：横屏左侧为时段与范围，右侧为结果。改任一处时两边都要检查。
- Auto teacher evaluation (`TeacherEvaluationService`/`TeacherEvaluationViewModel`) mirrors iOS/desktop behavior: first-visit protection wait (`TeacherEvaluationIndexProtection`, infoTime+5s), one immediate retry with a refreshed index token, verify-before-fail fallback, and one post-batch compensation round. Keep the three platforms consistent when touching it.

## Remote config

- `service/RemoteManifestService.kt` fetches `loveace/manifest_v2.json` (EdgeOne `loveace.linota.cn` first, `release.loveace.top` fallback) with `ignoreUnknownKeys`; unknown top-level fields are safe to add.
- OTA/update dialogs and announcements flow through `OtaService`/`OtaViewModel` (checked silently at app launch, before login).
- `prelogin_notice` is the pre-login banner rendered by `ui/screen/PreloginNoticeCard.kt` inside both login screens; fetch failures must stay silent and never block login. Publish/clear it via the `deploy-release-metadata.yml` workflow (`publish-prelogin` / `clear-prelogin`).

## UI conventions

- The app uses Compose Material3 Expressive (`androidx.compose.material3` 1.4.0). Loading uses the self-drawn flower loader `RibbonShapeLoader` through `AppCircularProgressIndicator`; Material3 1.4.0 has no `CircularWavyProgressIndicator` / `LinearWavyProgressIndicator`. Prefer these over introducing a different visual language.
- Keep changes surgical: many screens have separate portrait and landscape implementations; update both only when the feature is exposed in both modes.
- 节次、星期、教学周选择器是 `ui/md3e/RibbonSelector.kt` 的 `RibbonSlotGrid`（选项格，选中时圆角 spring 变形为胶囊）与 `RibbonWeekStrip`（周次横向条）。Material3 1.4.0 的公开 API 里没有 `ButtonGroup`、`ToggleButton`、`LoadingIndicator`，`ExperimentalMaterial3ExpressiveApi` 也是 internal，不要引用它们；Expressive 效果用 md3e 组件和 spring 变形实现。
