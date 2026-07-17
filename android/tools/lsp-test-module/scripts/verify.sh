#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

./gradlew \
  :app:testDebugUnitTest \
  :app:lintDebug \
  :app:lintRelease \
  :app:assembleDebug \
  :app:assembleRelease

APK_ANALYZER="${APK_ANALYZER:-$(command -v apkanalyzer || true)}"
test -n "$APK_ANALYZER"
test -x "$APK_ANALYZER"

verify_apk() {
  local apk="$1"
  local expected_entry="${2:-}"
  local module_entry
  local class_dump
  local manifest_dump

  test -f "$apk"

  for metadata_entry in \
    META-INF/xposed/java_init.list \
    META-INF/xposed/module.prop \
    META-INF/xposed/scope.list; do
    unzip -Z1 "$apk" | grep -Fx "$metadata_entry" >/dev/null
  done

  module_entry="$(unzip -p "$apk" META-INF/xposed/java_init.list | tr -d '\r\n')"
  test -n "$module_entry"
  if [[ -n "$expected_entry" ]]; then
    test "$module_entry" = "$expected_entry"
  fi

  unzip -p "$apk" META-INF/xposed/module.prop | grep -Fx 'minApiVersion=102' >/dev/null
  unzip -p "$apk" META-INF/xposed/module.prop | grep -Fx 'targetApiVersion=102' >/dev/null
  unzip -p "$apk" META-INF/xposed/module.prop | grep -Fx 'staticScope=false' >/dev/null
  unzip -p "$apk" META-INF/xposed/scope.list | grep -Fx 'tech.loveace.appv3' >/dev/null
  ! unzip -p "$apk" META-INF/xposed/scope.list | grep -F '.pr' >/dev/null

  manifest_dump="$("$APK_ANALYZER" manifest print "$apk")"
  grep -F 'android:icon=' <<<"$manifest_dump" >/dev/null
  grep -F 'android:roundIcon=' <<<"$manifest_dump" >/dev/null
  if [[ -n "$expected_entry" ]]; then
    unzip -Z1 "$apk" | grep -F 'res/mipmap-anydpi-v33/ic_launcher.xml' >/dev/null
  fi

  class_dump="$("$APK_ANALYZER" dex code --class "$module_entry" "$apk")"
  grep -F '.super Lio/github/libxposed/api/XposedModule;' <<<"$class_dump" >/dev/null

  printf 'Verified %s (entry: %s)\n' "$apk" "$module_entry"
}

DEBUG_APK="$ROOT/app/build/outputs/apk/debug/app-debug.apk"
RELEASE_APK="$ROOT/app/build/outputs/apk/release/app-release.apk"

verify_apk "$DEBUG_APK" "tech.loveace.testhook.ModernModuleEntry"
verify_apk "$RELEASE_APK"
