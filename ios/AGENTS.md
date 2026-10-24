# AGENTS.md

## Working flow
- Start by reading the relevant Swift/config files, then restate the requirement, make a short task list, and confirm with the user before non-trivial edits.
- Expect iterative direction changes; if the user interjects, pause, update the plan, and continue with the smallest correct diff.
- Preserve user work: run `git status --short` before edits, do not revert unrelated changes, and do not commit unless explicitly asked.

## Project map
- Xcode project only: `loveaceios.xcodeproj`; schemes/targets are `loveaceios` and `loveaceiosWidget`.
- Main app: bundle `cn.linota.loveace`, display name `彩带小工具`; widget: bundle `cn.linota.loveace.widget`; team `2PYK4BY5P6`.
- App and widget share `group.cn.linota.loveace`; widget data bridge is `Shared/WidgetModels.swift` via `UserDefaults(suiteName:)`.
- SwiftUI flow: `loveaceiosApp.swift` creates `AuthViewModel` -> `ContentView` restores/routes auth -> `MainTabView` tabs (`HomeView`, `AACView`, `MoreView`, `SettingsView`).
- Services live in `loveaceios/Service` and are wired in `AuthViewModel.initServices(_:)`; login/session networking is `AUFEConnection` + `HTTPClient`.
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

## Login captcha and cooldown

- `AUFEConnection.ecLogin(captchaCode:)` is the only EC entry point. Without a code it returns `captchaRequired` with `captchaImage` when the auth page has `<RndImg>1</RndImg>` or the POST answers 20041. With a code it must reuse the actor's pending auth context (single-use, 180 s); a 20023 answer is `captchaInvalid`, which counts as a failure and triggers a fresh challenge.
- `AuthViewModel` keeps the connection that issued the challenge while credentials are unchanged; a changed userId or password starts a new connection.
- `LoginThrottle` (in `AuthViewModel.swift`) stores UserDefaults keys `login_throttle.failures.<userId>` and `login_throttle.cooldown_until.<userId>`. The ladder is 1 → none, 2 → 30 s, 3 → 120 s, ≥4 → 600 s; success clears both keys. Only wrong-password and captcha-invalid count; network errors and captcha prompts do not.
- Auto-reconnect and `restoreSession` that hit a captcha keep the saved credentials and return to the login screen with "学校要求输入验证码，请重新登录". Do not clear credentials on that path.
- Do not map 20041 back to "登录频繁"; it means captcha required.
- Full-width checks live in `Util/TextValidation.swift`. Keep them aligned with Android `util/TextValidation.kt` and desktop `utils/text_validation.dart`.

## Git/artifact quirks
- `.gitignore` ignores `build/`, `DerivedData/`, `*.xcarchive`, `*.ipa`, `*.dSYM`, SPM build folders, and Xcode user state.
- `build/` was previously tracked; treat staged deletions or ignored archives as artifacts and do not restore or commit them unless the user explicitly requests it.

## Course schedule query and free classroom (iOS)
- Services: `Service/CourseScheduleService.swift` (`loadIndex`, `queryPage`, page size 20; record id uses the same 8-field key as Android `courseRecordKey`) and `Service/FreeClassroomService.swift` with pure rules in `Service/FreeClassroomRules.swift`. Endpoints and rules mirror Android `CourseScheduleService` and `FreeClassroomService`; change both platforms together.
- The free-classroom search only returns status 01 rooms, so it supplies the free set. Results show every room of the scoped buildings grouped by floor, loaded from `classroomJson` and cached per building in the view model; stopped buildings and rooms with status 02/03 are hidden unless "显示停用教室" is on (`free_classroom.show_stopped` in UserDefaults).
- School JSON fields may be numbers or strings: use `jsonInt`, `jsonText`, `jsonObjectArray` from `Util/JSONFlex.swift`, not `as? Int`.
- Liquid Glass: use `compatGlassProminentButtonStyle()` only for floating primary actions. List rows and detail content stay on system materials.
