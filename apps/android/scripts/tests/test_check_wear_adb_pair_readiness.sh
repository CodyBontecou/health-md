#!/usr/bin/env bash
set -euo pipefail

fail() { echo "ADB pair readiness policy test: $*" >&2; exit 1; }
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fake="$tmp/adb"
cat >"$fake" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
scenario=${FAKE_ADB_SCENARIO:?}
if [[ ${1:-} == devices ]]; then
  echo 'List of devices attached'
  case "$scenario" in
    pair|pair-feature)
      printf 'phone-1\tdevice\nwatch-1\tdevice\n'
      ;;
    two-phones)
      printf 'phone-1\tdevice\nphone-2\tdevice\n'
      ;;
    two-watches)
      printf 'watch-1\tdevice\nwatch-2\tdevice\n'
      ;;
    offline)
      printf 'phone-1\toffline\nwatch-1\tunauthorized\n'
      ;;
    *) exit 64 ;;
  esac
  exit 0
fi
[[ ${1:-} == -s && ${3:-} == shell ]] || exit 64
serial=$2
if [[ ${4:-} == getprop && ${5:-} == ro.build.characteristics ]]; then
  case "$serial" in
    watch-*) [[ "$scenario" == pair-feature ]] || echo 'watch,nosdcard' ;;
    *) echo 'nosdcard' ;;
  esac
  exit 0
fi
if [[ ${4:-} == pm && ${5:-} == list && ${6:-} == features ]]; then
  [[ "$serial" == watch-* && "$scenario" == pair-feature ]] && echo 'feature:android.hardware.type.watch'
  exit 0
fi
exit 64
EOF
chmod +x "$fake"

for scenario in pair pair-feature; do
  output=$(FAKE_ADB_SCENARIO=$scenario ADB="$fake" "$root/check-wear-adb-pair-readiness.sh")
  [[ "$output" == *'availability only'* && "$output" == *'phones=1 watches=1'* ]] \
    || fail "$scenario did not identify one phone and one watch"
done
for scenario in two-phones two-watches offline; do
  if FAKE_ADB_SCENARIO=$scenario ADB="$fake" "$root/check-wear-adb-pair-readiness.sh" >/dev/null 2>&1; then
    fail "$scenario incorrectly passed as a phone/watch pair"
  fi
done

echo 'ADB pair readiness policy tests passed'
