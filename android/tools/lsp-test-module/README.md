# LoveACE LSP Test Module

A standalone libxposed API 102 test tool for LoveACE. It combines opt-in response fixtures with
sanitized request tracing and runtime diagnostics without changing the production application
source or release build.

The project lives entirely under `android/tools/lsp-test-module/` and has its own Gradle wrapper.
It is not included from `android/settings.gradle.kts`.

## Capabilities

### Runtime diagnostics

- Dynamic scope (`staticScope=false`) with in-app discovery of installed `tech.loveace.appv3.*`
  variants. The bundled scope list contains only the production package as a recommendation.
- Target recognition by the LoveACE `HttpClient` class and OkHttp request/response signature, so
  hooks are not tied to a specific PR package suffix or private method name.
- LSPosed framework, API, scope, running PID, target state, and loaded module version display.
- Optional request trace for method, host/path, duration, HTTP status, transport, and Mock versus
  passthrough outcome.
- Query parameters, fragments, credentials, headers, cookies, request bodies, and response bodies
  are excluded from request traces.
- Copyable diagnostics and recent trace history, capped at 40 records.

### Response fixtures

- Master switch plus nine independently selectable read-only data-source groups.
- Exam-only preset that leaves academic GPA, ranking, and failed-course totals on the real path.
- Dynamic dates and scenarios for active, upcoming, completed, empty, malformed, HTTP 503, and
  custom exam states.
- Configurable response delay, course, room, seat, semester boundary, date offset, start offset,
  and duration.
- Preview and copy support for every generated response.

| Switch | Request | Format |
| --- | --- | --- |
| Semester calendar | `semesters.json` | JSON |
| Academic overview | `/main/academicInfo` | JSON array |
| Exam index and seat | `/examPlan/index` | HTML |
| School exams | `/examPlan/detail` | JSON array |
| Other exams | `/othersExamPlan/queryScores` | JSON object |
| Scores | score index + dynamic `allTermScores/data` | HTML + JSON |
| Schedule | term index, student schedule, course catalog | HTML + JSON |
| Campus card | session, balance, transaction list | HTML |
| Training plan | plan summary + completion tree | JSON + HTML |

Disabled sources and all write requests use the original path. Observation mode is independent of
the Mock master switch and can inspect real passthrough requests without replacing responses.

## Build

Requirements:

- JDK 17
- Android SDK 37
- An API 102-compatible LSPosed implementation

```bash
cd android/tools/lsp-test-module
./scripts/verify.sh
```

Outputs:

```text
app/build/outputs/apk/debug/app-debug.apk
app/build/outputs/apk/release/app-release.apk
```

Install the Debug build and open the module app:

```bash
./scripts/install-debug.sh
```

The app discovers installed LoveACE application-ID variants and can request them through the API
102 service. Other packages can also be added from LSPosed because the module does not use a static
scope; packages without the LoveACE HTTP client signature are ignored.

## Wired ADB control

The Debug build exposes a receiver that is omitted from Release:

```bash
ANDROID_SERIAL=SERIAL ./scripts/adb-config.sh this_week
ANDROID_SERIAL=SERIAL ./scripts/adb-trace.sh on
ANDROID_SERIAL=SERIAL ./scripts/adb-trace.sh clear
ANDROID_SERIAL=SERIAL ./scripts/adb-trace.sh off
```

Useful framework logs:

```bash
adb logcat | rg 'LoveACELspTest|Mock (SEMESTER|ACADEMIC|SCORES|SCHEDULE|CAMPUS|TRAINING)'
```

## Guardrails

- Mock and request tracing both default to off.
- HTTP method, host, and path must all match before a fixture is returned.
- Campus-card recharge and every other write endpoint always pass through.
- Hook exceptions use API 102 protective mode.
- Trace storage contains no account data, credentials, tokens, headers, bodies, or captured
  responses.
- Recent traces are a bounded diagnostic buffer and can be cleared from the app or ADB.
- Generated APKs, signing files, and local target builds remain outside Git.

## Verification

`./scripts/verify.sh` runs fixture-contract tests, request-trace privacy tests, real OkHttp reflection
tests, Debug/Release lint, and Debug/Release/R8 assemblies. It also verifies API 102 metadata,
dynamic scope, adaptive launcher resources, the recommended production scope, and that each
packaged entry resolves to a DEX class extending `XposedModule`.
