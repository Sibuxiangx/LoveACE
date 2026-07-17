#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APK="$ROOT/app/build/outputs/apk/debug/app-debug.apk"

if [[ ! -f "$APK" ]]; then
  "$ROOT/gradlew" -p "$ROOT" :app:assembleDebug
fi

adb install -r "$APK"
adb shell monkey -p tech.loveace.testhook 1 >/dev/null
