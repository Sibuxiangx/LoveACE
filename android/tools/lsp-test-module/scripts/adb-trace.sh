#!/usr/bin/env bash
set -euo pipefail

ADB="${ADB:-adb}"
SERIAL="${ANDROID_SERIAL:-}"
MODE="${1:-on}"

if [[ -z "$SERIAL" ]]; then
  SERIAL="$($ADB devices | awk 'NR > 1 && $2 == "device" { print $1 }' | head -1)"
fi
test -n "$SERIAL"

"$ADB" -s "$SERIAL" shell am start -W \
  -n tech.loveace.testhook/.MainActivity >/dev/null

case "$MODE" in
  on) args=(--ez trace true) ;;
  off) args=(--ez trace false) ;;
  clear) args=(--ez clear_trace true) ;;
  *) printf 'Usage: %s [on|off|clear]\n' "$0" >&2; exit 2 ;;
esac

for attempt in 1 2 3 4 5; do
  result="$($ADB -s "$SERIAL" shell am broadcast -W \
    -a tech.loveace.testhook.DEBUG_CONFIG \
    -n tech.loveace.testhook/.DebugConfigReceiver \
    "${args[@]}")"
  if [[ "$result" == *'data="applied"'* ]]; then
    printf 'Trace %s applied on %s\n' "$MODE" "$SERIAL"
    exit 0
  fi
  sleep 1
done

printf '%s\n' "$result" >&2
exit 1
