#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADB="${ADB:-adb}"
SERIAL="${ANDROID_SERIAL:-}"
SCENARIO="${1:-this_week}"

if [[ -z "$SERIAL" ]]; then
  SERIAL="$($ADB devices | awk 'NR > 1 && $2 == "device" { print $1 }' | head -1)"
fi
test -n "$SERIAL"

"$ADB" -s "$SERIAL" shell am start -W \
  -n tech.loveace.testhook/.MainActivity >/dev/null

for attempt in 1 2 3 4 5; do
  result="$($ADB -s "$SERIAL" shell am broadcast -W \
    -a tech.loveace.testhook.DEBUG_CONFIG \
    -n tech.loveace.testhook/.DebugConfigReceiver \
    --ez enabled true \
    --ez semester true \
    --ez academic false \
    --ez exam_index true \
    --ez school_exams true \
    --ez other_exams true \
    --ez scores false \
    --ez schedule false \
    --ez campus_card false \
    --ez training_plan false \
    --es scenario "$SCENARIO")"
  if [[ "$result" == *'data="applied"'* ]]; then
    printf 'Applied %s on %s\n' "$SCENARIO" "$SERIAL"
    exit 0
  fi
  sleep 1
done

printf '%s\n' "$result" >&2
exit 1
