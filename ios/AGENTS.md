# AGENTS.md

## Working flow
- Start by reading the relevant Swift/config files, then restate the requirement, make a short task list, and confirm with the user before non-trivial edits.
- Expect iterative direction changes; if the user interjects, pause, update the plan, and continue with the smallest correct diff.
- Preserve user work: run `git status --short` before edits, do not revert unrelated changes, and do not commit unless explicitly asked.

## Project map
- Xcode project only: `loveaceios.xcodeproj`; schemes/targets are `loveaceios` and `loveaceiosWidget`.
- Main app: bundle `cn.linota.loveace`, display name `彩带小工具`; widget: bundle `cn.linota.loveace.widget`; team `2PYK4BY5P6`.
- App and widget share `group.cn.linota.loveace`. The widget reads one versioned snapshot (`WidgetSnapshotStore`, key `widget_snapshot_v2`) and the shared schedule rules in `Shared/WidgetModels.swift`. Only `WidgetSyncCoordinator` writes the snapshot; widgets never fetch.
- SwiftUI flow: `loveaceiosApp.swift` creates `AuthViewModel` -> `ContentView` restores/routes auth -> `AdaptiveRootView`. iPhone is portrait-only (the orientation keys in `project.pbxproj` say so). On iPad, landscape (width > height) shows a fixed 180 pt sidebar (an `HStack` with a `List`, not `NavigationSplitView`, so it cannot collapse and has no toggle) beside the detail page; portrait shows a `TabView` (`HomeView`, `AACView`, `MoreView`, `SettingsView`). The selection is `AppDestination` at the root, so rotating keeps the current page.
- Navigation: each feature page owns its single `NavigationStack`. `AdaptiveRootView` does not wrap feature pages, and a page must not wrap itself in a second stack. The electricity page's `NavigationStack(path:)` is the only stack on its screen.
- The feature catalog lives in `View/AppCatalog.swift` (`AppCatalog.sections` and `AppCatalog.destinationView(for:)`) and is shared by the More tab and the iPad sidebar. Add a new feature there, in 教务服务 / 校园生活 / 素质拓展 (the same taxonomy as the Android landscape nav), not as a new tab. The More tab's search filters the same list.
- Wide layout (P2): `AdaptiveRootView` injects `\.wideLayout` (true only in the iPad landscape sidebar layout, never on iPhone). Pages that need two columns or a split read it with `@Environment(\.wideLayout)`; compact (iPhone and iPad portrait) keeps the single column. `readableWidth(_:)` (in `Components/AdaptiveLayout.swift`) caps content width and centers it. `wideRowSelection(_:tint:)` (same file) draws the inset rounded selection background for wide list rows. Current use: Home (full-width semester banner; below it the GPA card on the left, and in a 340 pt column on the right the campus card, three status tiles and the insights link), AAC (two columns: a 340 pt left column with the credit header and category list, the selected category detail on the right), Plan (two columns: a 340 pt left column with the summary and category list, the selected category detail on the right, with subcategory drill-in), Competition (two columns: credits and awards list | selected award detail), Labor 劳动课 (two columns: progress, clubs, tabs and activity list | selected activity detail), Access (two columns: query controls | records), Borrowing (two columns: current loans | history), Free classroom (two columns: time selection | results), YKT (two columns: balance and transfer | records), Login (brand panel left, form right, 440 pt form width), Settings and More (680 pt cap, More keeps two columns).
- List detail (P3): list-driven detail panels use `.detailPanel(item:)` (`Components/DetailPanel.swift`). On iPad landscape it is a trailing `inspector`; elsewhere it stays a `sheet`. Detail views declare `@DetailDismiss private var dismiss` (call `dismiss()` as usual) and must have a 关闭 toolbar button, because an inspector has no swipe-to-dismiss. Still on `detailPanel` (inspector in wide): scores, repair orders, course schedule query, free classroom rooms. Column pages (AAC, plan, competition, labor) select inside the page in wide and never use `.inspector`; compact keeps their sheets via `detailPanel`. Timetable grids (`ScheduleView`, `SemesterScheduleView`) still use sheets.
- Services live in `loveaceios/Service` and are wired in `AuthViewModel.initServices(_:)`; login/session networking is `AUFEConnection` + `HTTPClient`.
- Login diagnostics (iOS): `Network/LoginDiagnostics.swift` keeps the last 10 login attempts (always on, not behind the network-log switch) in `Application Support/LoveACE/LoginDiagnostics/attempts.json`. Each attempt is a PCL-style log: `[HH:mm:ss.SSS] [LEVEL] [MODULE] text`. `HTTPClient.execute` records each round trip while a login is active: compressed URL, status, duration, content type, response header names, request header values (sensitive ones masked), form field values, response excerpt (masked, 800 chars), and keyword markers. `AuthViewModel.authenticate` records each EC and UAAP result as presence flags only. Masking: sensitive values become codes such as `<Password>`, `<SetCookie>`, `<Lt>`; student IDs keep the first and last two digits; binary bodies log size only. The login page shows "分享登录诊断" when a failure exists (`View/LoginDiagnosticsButton.swift`). Tapping it shows a consent alert, then `Network/DiagnosticsUploader.swift` POSTs `diagnostic.json` (contract v1 to `/v1/diagnostics`, same Bearer + HMAC signing as `/v1/events`, local 1 MiB cap that fails before any request). Success shows a result sheet with the `diag.html` link, a copy button, and the 加入用户群 entry. The server returns `diag.html` and `llm.md` links that expire after 3 days. Never put bodies, cookies, tokens, passwords, or captcha content into the log or the upload.
- Reuse `loveaceios/Components/DesignSystem.swift` (`glassCard`, `glassInteractiveCard`, `GlassBadge`, etc.) for UI instead of ad-hoc styling.
- SPM dependency is SwiftSoup, resolved in `loveaceios.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

## Build and simulator checks
- Inspect schemes with `xcodebuild -list -project loveaceios.xcodeproj`.
- Debug simulator build:
  ```sh
  xcodebuild -project loveaceios.xcodeproj -scheme loveaceios -configuration Debug -destination 'generic/platform=iOS Simulator' build
  ```
- For simulator install/launch, build to a deterministic DerivedData path first:
  ```sh
  xcodebuild -project loveaceios.xcodeproj -scheme loveaceios -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData build
  xcrun simctl terminate booted cn.linota.loveace || true
  xcrun simctl install booted build/DerivedData/Build/Products/Debug-iphonesimulator/loveaceios.app
  xcrun simctl launch booted cn.linota.loveace
  ```
- There is no test target; verify with focused `xcodebuild` plus simulator/manual checks unless tests are added.
- Xcode 27 renamed the simulator UI app to DeviceHub: it lives inside `/Applications/Xcode.app/Contents/Applications/DeviceHub.app` (not Spotlight-searchable); `open -a DeviceHub` opens it. The user now tests on real devices — recreate simulator devices only on demand.
- Swift 6 strict concurrency: string-interpolation captures of actor properties need explicit `self.` (or copy to a local first) — interpolation counts as a closure.
- A duplicate build-file warning for `Shared/WidgetModels.swift` may appear; do not clean up project settings unless the user asks.

## TestFlight upload
- If the user asks for TestFlight, ask how to bump version/build first; default to keeping `MARKETING_VERSION` and incrementing `CURRENT_PROJECT_VERSION` for both app and widget.
- Verify/update all four `CURRENT_PROJECT_VERSION` entries in `loveaceios.xcodeproj/project.pbxproj` before archiving.
- `ExportOptions.plist` is configured for App Store Connect upload: `method=app-store-connect`, `destination=upload`, team `2PYK4BY5P6`, automatic signing, symbols on.
- Archive/upload from repo root:
  ```sh
  mkdir -p build/TestFlight
  ARCHIVE_PATH="build/TestFlight/loveaceios-$(date +%Y%m%d-%H%M%S).xcarchive"
  xcodebuild -project loveaceios.xcodeproj -scheme loveaceios -configuration Release -destination 'generic/platform=iOS' -archivePath "$ARCHIVE_PATH" -allowProvisioningUpdates archive
  xcodebuild -exportArchive -archivePath "$ARCHIVE_PATH" -exportOptionsPlist ExportOptions.plist -exportPath "build/TestFlight/export-$(date +%Y%m%d-%H%M%S)" -allowProvisioningUpdates
  ```
- If upload fails with `Failed to Use Accounts`, the local Xcode App Store Connect login likely expired; ask the user to re-login in Xcode Settings > Accounts, then retry the same archive.

## CI (TestFlight)
- `.github/workflows/ios-testflight.yml` is `workflow_dispatch` with `dry_run` (default `true`: archive, sign, upload artifact, no TestFlight upload). Trigger a real upload with `gh workflow run ios-testflight.yml --ref main -f dry_run=false`.
- Every run revokes the distribution certificates/profiles it created at the end (`always()` cleanup step). If a run still fails with "reached the maximum number of certificates", historical certificates need manual revocation on developer.apple.com — the API key may not be able to see/revoke those.

## Pre-login notice
- `AnnouncementService.fetchPreloginNotice()` reads the optional top-level `prelogin_notice` field of manifest v2; `LoginView` renders the banner below the brand header and must stay silent on fetch failure. Desktop ignores this field.
- QQ group entry: `QqGroupService.fetch()` (`Service/QqGroupService.swift`) reads `qq_group_v1.json` (key `qq_group_v1.json`, not manifest_v2), tries `loveace.linota.cn` then `release.loveace.top`, and shows entries only when `schema_version == 1` and `enabled == true`. Result is in-memory per screen, never persisted or logged. UI: `QqGroupEntryCard` under the login button and `QqGroupSettingsRow` in 我的, both opening `QqGroupPopup` (`View/QqGroupPopup.swift`).

## Login captcha and cooldown

- `AUFEConnection.ecLogin(captchaCode:)` is the only EC entry point. Without a code it returns `captchaRequired` with `captchaImage` when the auth page has `<RndImg>1</RndImg>` or the POST answers 20041. With a code it must reuse the actor's pending auth context (single-use, 180 s); a 20023 answer is `captchaInvalid`, which counts as a failure and triggers a fresh challenge.
- `AuthViewModel` keeps the connection that issued the challenge while credentials are unchanged; a changed userId or password starts a new connection.
- `LoginThrottle` (in `AuthViewModel.swift`) stores UserDefaults keys `login_throttle.failures.<userId>` and `login_throttle.cooldown_until.<userId>`. The ladder is 1 → none, 2 → 30 s, 3 → 120 s, ≥4 → 600 s; success clears both keys. Only wrong-password and captcha-invalid count; network errors and captcha prompts do not.
- Auto-reconnect and `restoreSession` that hit a captcha keep the saved credentials and return to the login screen with "学校要求输入验证码，请重新登录". Do not clear credentials on that path.
- Do not map 20041 back to "登录频繁"; it means captcha required.
- Full-width checks live in `Util/TextValidation.swift`. Keep them aligned with Android `util/TextValidation.kt` and desktop `utils/text_validation.dart`.
- Weak school password hint (`isWeakSchoolPassword` in `Util/TextValidation.swift`, same rule as Android): the manual login form shows an alert before submitting; "继续登录" submits anyway. Hint only; quick login and auto-reconnect skip it.
- The gateway-password option was removed; login uses one password (the gateway parameter is passed as nil).
- `ContentView` keeps `LoginView` mounted during `.loading`; do not swap it for a loading view. Rebuilding the login view on error wipes typed input, re-prefills remembered credentials, and `userIdDidChange` then clears the captcha. Prefill only when the userId and password fields are empty. The userId and password fields have no `textContentType`, so system AutoFill cannot overwrite what the user typed.

## Git/artifact quirks
- `.gitignore` ignores `build/`, `DerivedData/`, `*.xcarchive`, `*.ipa`, `*.dSYM`, SPM build folders, and Xcode user state.
- `build/` was previously tracked; treat staged deletions or ignored archives as artifacts and do not restore or commit them unless the user explicitly requests it.

## Course schedule query and free classroom (iOS)
- Services: `Service/CourseScheduleService.swift` (`loadIndex`, `queryPage`, page size 20; record id uses the same 8-field key as Android `courseRecordKey`) and `Service/FreeClassroomService.swift` with pure rules in `Service/FreeClassroomRules.swift`. Endpoints and rules mirror Android `CourseScheduleService` and `FreeClassroomService`; change both platforms together.
- The free-classroom search only returns status 01 rooms, so it supplies the free set. Results show every room of the scoped buildings grouped by floor, loaded from `classroomJson` and cached per building in the view model; stopped buildings and rooms with status 02/03 are hidden unless "显示停用教室" is on (`free_classroom.show_stopped` in UserDefaults).
- School JSON fields may be numbers or strings: use `jsonInt`, `jsonText`, `jsonObjectArray` from `Util/JSONFlex.swift`, not `as? Int`.
- Liquid Glass: use `compatGlassProminentButtonStyle()` only for floating primary actions. List rows and detail content stay on system materials.

## Teacher evaluation (iOS)

- Services: `Service/TeacherEvaluationService.swift` (actor), `ViewModel/TeacherEvaluationViewModel.swift`, `View/TeacherEvaluationView.swift`. Endpoints and flow mirror Android `TeacherEvaluationService`; change both together.
- Each course fetches a fresh index token inside `prepareEvaluation`; there is no actor-level token cache.
- Read requests (index, search, evaluationPage) retry on `URLError` up to 3 attempts; the assessment POST never retries.
- An unconfirmed submit is verified first. If verification fails the course is `verifyUnknown` and is never resubmitted. Only a verified "not evaluated" result allows one fresh prepare, a 140 s wait, and one more submit.
- Post-batch compensation runs only for `prepareFailed`/`submitFailed` courses, after a successful list refresh; `verifyUnknown` is excluded.
- A VPN login-page response is reported as "会话已失效，请重新登录"; `URLError` maps to a Chinese message, so raw `localizedDescription` text does not reach the UI.
- `TeacherEvaluationView.onDisappear` calls `cancelEvaluation()`, which stops the batch and marks unfinished tasks cancelled. Android and desktop keep the batch running after the page is left; iOS stays different until the user asks to unify.

## Widget, Live Activity, and class reminders

- Session times come from the school's `sectionTime` (`SchoolCalendar`): 45 minutes per session, 10 sessions per day. Do not reintroduce a 50-minute table. Android `SESSION_TIMES` matches sessions 1-10 but also lists session 11 (20:50), which the school data does not have.
- Sync triggers: `ContentView` runs `WidgetSyncCoordinator.sync` on each new session (`sessionGeneration`, covers login and auto-reconnect) and on every foreground. Sync is throttled to 30 minutes per user. A failed fetch keeps the old snapshot; a successful one overwrites it and calls `reloadAllTimelines` once. Do not call `reloadAllTimelines` from view models.
- Week number, vacation countdown, and "学期即将结束" are computed in the widget from `SchoolTerm.phase` and the semester list. They do not depend on the app being opened.
- The timeline reads the snapshot once and emits entries only at today's and tomorrow's class boundaries, with refresh after the next midnight. The medium widget shows only unfinished classes (in-progress first), never a `prefix` of the full day.
- Live Activity (`CourseActivityAttributes`): `CourseLiveActivityController.sync` starts it from 10 minutes before a class until it ends, only while the app is in the foreground. `StartCourseActivityIntent` (`LiveActivityIntent`, also a widget button) can start it from the background when the user taps. There is no automatic start at class time without APNs push-to-start, which needs a server. An activity the app never ends lasts up to 8 hours, plus 4 hours on the Lock Screen. `NSSupportsLiveActivities` lives in `ios/Info.plist`.
- Class reminders (`ClassReminderScheduler`): local notifications 10 minutes before class, for the next 14 days, capped at 60 pending. Identifiers are deterministic, so re-scheduling replaces rather than duplicates. Enabled from Settings > 上课提醒, which requests permission on toggle. Pending-count limit is from third-party sources; verify on device.
- Logout and automatic sign-out call `WidgetSyncCoordinator.clearAll()`, which clears the snapshot, reminders, and Live Activities.
- Exams (iOS): once teaching ends (start + weeks × 7 days) and an exam dated today or later exists, `SchoolTerm.phase` returns `TermPhase.examWeek` (Home 考试周, widget exam card). Exams inside the teaching period are `ScheduleItem`s on their date, and `WidgetScheduleState.next` moves to an exam when the earlier item ends. Exam reminders fire at 20:00 the day before each exam (`ClassReminderScheduler.examRequests`; same toggle and permission as class reminders; `clearAll` cancels them). Entering home after login force-prefetches schedule, semesters and exams from `ContentView` (no 30-minute throttle, in background); failure keeps the old snapshot, success posts `WidgetSyncCoordinator.snapshotDidChange`.

## Portal features: mail password, access records, borrowing (iOS)
- Service: `Service/PortalService.swift` (actor), API base `all-aufe-edu-cn-s.vpn2.aufe.edu.cn:8118` (the `-s` host the server lands on after CAS; the plain `all-aufe-edu-cn` host 301s and then 405s on POST, see netlog A216E7A5). Session: the same UAAP CAS entry as JWC and AAC (`uaap-aufe-edu-cn.vpn2…:8118/cas/login?service=<non-VPN cas-entrance URL>`), followed hop by hop through `noRedirectClient` with `*.aufe.edu.cn` hosts mapped to the VPN host; then `POST /api/portal/homepage/hpdata` gives `hpinfo.userid`, which is the `hrmResourceID`. A non-JSON answer means the session expired. Each hop logs status, host and path.
- All three features read cubes with `getList` → `ec/dev/table/counts` → `ec/dev/table/datas` (10 rows per page, `current` paged). Fields are matched by column title, then `dbField`, never by index.
- Access records (门禁) are minimal and paged. The body is `customid`, `hrmResourceID`, `guid=search`, `canIsQuickSearch=1`, `isNewTableSearch=1`, the display and window fields, and only the cube's date field (dorm `178950`, library `316587`). Codes: 今天=1, 昨天=9, 本周=2 (library default `2,,`), 本月=3, 全部=0. The first page loads by default (本周); `加载更多` pages on demand. Never send the quick-search flags or 全部 by default. Dorm `通过方向` arrives as `0`/`1` and maps to `AccessDirection` through `PortalService.direction` (0=进, 1=出, checked against the portal screenshot); each dorm row shows a green walk-in / orange walk-out figure (`figure.walk.arrival` / `figure.walk.departure`, the emergency-exit style). Library rows have no direction field and no icon. Switching type or range clears results; stale responses are dropped by generation.
- The mail password is memory-only. `NetworkLogRedactor.bodyOmittedPathSuffixes` keeps `/api/ec/dev/table/datas` response bodies out of the network log because the mail cube returns the password in plaintext. Keep that exclusion when touching the log. `MailPasswordViewModel` drops stale responses with a generation counter, and `clear()` bumps it so a response that arrives after the page is left cannot write the password back.
- `MailInitialPasswordView` is the scratch-off card: a `.ultraThinMaterial` rectangle masked by a `Canvas` that erases drag paths with `.destinationOut`. Copy is the context-menu long press and expires after 60 s. The password is cleared on disappear.
- Access records (`AccessRecordsView`) show the dormitory delayed-sync note; the library list has none. Borrowing (`BorrowingView`) shows current loans under 正在借阅 with a green `book.fill` and history under 借阅历史 with an orange `book.closed.fill`; the icon is chosen by the section, not inferred from fields. `BorrowingViewModel` drops stale responses with a generation counter. A refresh failure after a successful load keeps both lists and shows the error above them with 重试; only a first-load failure replaces the content with the error state.
- Campus card (`YKTView`/`YKTViewModel`): balance still comes from ykt (`YKTService.getBalance`, `initSession`), because the portal has no balance column. Consumption records now come from the portal cube 74507 (`PortalService.consumptionRecords`, default 本月 via date field `299018=3`, 100 rows per page, `加载更多`). The portal row has date, time, area and amount only: no balance after each transaction, no transaction type, and no income/expense sign. `ykt` `queryUserCostList` and `TransactionRecord` were removed. Home (`HomeView`) calls `loadBalance()` only. A balance error renders in the balance hero with 重试. A consumption error renders with 重试: it replaces the list on the first page, and sits inline under the list on load-more. When the first page loads with zero rows the card shows 本月暂无消费记录; before the first load it shows nothing (`consumptionLoaded`).
- Portal requests send `X-Requested-With: XMLHttpRequest`, `Referer: <portal base>/spa/portal/static/index.html`, and `sdp-app-session` (the VPN session id, same as AAC and the labor club). Every successful `hpdata` in the logs carried `sdp-app-session`; the two that omitted it were intercepted. Repeated full logins or session setups within a few minutes can trigger the gateway's `404` with `Errormsg: securityIntercept`, so session setup is single-flight and a `securityIntercept` starts a 180 s cooldown (the recovery window is one observation, not a measured limit). Browser comparison (VPN login page in a browser, same portal, same `hpdata` request): `hpdata` carries `sf_request_type=fetch` in the query, the same `X-Requested-With`, and the Referer above; the browser also requested `/sf-webproxy/api/vpn-config` 4 times during the portal load. The App now sends the query parameter (`PortalService.apiURL` on all 7 portal API URLs), the Referer, and one `vpn-config` GET before `hpdata` (`ensureSession`). This is an untested change: no evidence yet that it fixes `securityIntercept`, and the App has not been run against the gateway with it.
- Entries: 更多 → 校园生活 (门禁查询, 我的借阅); 我的 → 账号 → 企业邮箱初始密码. Services are created in `AuthViewModel.initServices` and cleared in `clearServices`.
- Not the same as 门卡 (`DoorCardService`, BLE door card on spoyn.cn).
<parameter name="i">Documenting the portal features, the log exclusion, and the scratch-card implementation in ios/AGENTS.md
