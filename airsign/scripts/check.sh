#!/usr/bin/env bash
set -euo pipefail

COVERAGE_FLOOR=85

fail() {
  echo "check failed: $1" >&2
  exit 1
}

WITH_TEST_VOLUME=0
case "$#:${1:-}" in
  0:) ;;
  1:--with-test-volume) WITH_TEST_VOLUME=1 ;;
  *) echo "Usage: $0 [--with-test-volume]" >&2; exit 2 ;;
esac

cd "$(dirname "$0")/.."
PACKAGE_ROOT="$PWD"
REPO_ROOT="$(cd .. && pwd)"
WORK_DIR=
VOLUME_MOUNT=

cleanup() {
  if [[ -n "$VOLUME_MOUNT" ]]; then
    if ! hdiutil detach "$VOLUME_MOUNT" >/dev/null 2>&1 &&
       ! hdiutil detach -force "$VOLUME_MOUNT" >/dev/null 2>&1; then
      # A failed attach can leave an empty folder; never delete a mounted volume.
      [[ ! -d "$VOLUME_MOUNT" ]] || rmdir "$VOLUME_MOUNT" || return 1
    fi
    VOLUME_MOUNT=
  fi
  if [[ -n "$WORK_DIR" ]]; then
    rm -rf "$WORK_DIR" || return 1
    WORK_DIR=
  fi
}

bundle_strings() {
  local binary="$1" output="$2" assembly="$3"
  strings "$binary" > "$output" || return 1
  # Optimized arm64 Swift small strings can live in mov/movk immediates.
  xcrun llvm-objdump --disassemble --no-show-raw-insn "$binary" > "$assembly" || return 1
  awk '
    function hex(s, n, i) {
      sub(/^#0x/, "", s); sub(/,$/, "", s)
      n = 0
      for (i = 1; i <= length(s); i++) n = 16 * n + index("0123456789abcdef", tolower(substr(s, i, 1))) - 1
      return n
    }
    function emit( i, n) {
      if (have) for (i = 0; i < 4; i++) {
        n = word[i] + 0
        printf "%c%c", n % 256, int(n / 256)
      }
      for (i in word) delete word[i]
      have = 0
    }
    {
      if (($2 == "mov" || $2 == "movk") && $3 ~ /^x[0-9]+,$/ &&
          $4 ~ /^#0x[[:xdigit:]]+,?$/ && hex($4) <= 65535) {
        if ($2 == "mov") { emit(); register = $3; have = 1 }
        if (have && register == $3) {
          shift = ($5 == "lsl" ? substr($6, 2) + 0 : 0)
          word[shift / 16] = hex($4)
          next
        }
      }
      if (have) { emit(); printf "\n" }
    }
    END { if (have) { emit(); printf "\n" } }
  ' "$assembly" | strings >> "$output"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/airsign-check.XXXXXX")" || fail build

SWIFT_ARGS=()
IFS=' ' read -r -a SWIFT_ARGS <<< "${AIRSIGN_SWIFT_ARGS:-}"
DEBUG_ARGS=(--enable-code-coverage -Xswiftc -warnings-as-errors)

echo "==> 1/6 build"
swift build --build-tests "${DEBUG_ARGS[@]}" ${SWIFT_ARGS[@]+"${SWIFT_ARGS[@]}"} || fail build
swift build -c release --product AirSign -Xswiftc -warnings-as-errors \
  --scratch-path .build/check-default ${SWIFT_ARGS[@]+"${SWIFT_ARGS[@]}"} || fail build
swift build -c release --product AirSign -Xswiftc -DAIRSIGN_LAB -Xswiftc -warnings-as-errors \
  --scratch-path .build/check-lab ${SWIFT_ARGS[@]+"${SWIFT_ARGS[@]}"} || fail build

echo "==> 2/6 tests"
if [[ "$WITH_TEST_VOLUME" == 1 ]]; then
  hdiutil create -size 16m -fs ExFAT -volname AIRSIGNCHK -ov "$WORK_DIR/vol.dmg" || fail "test volume"
  VOLUME_MOUNT="$WORK_DIR/mnt"
  mkdir -p "$VOLUME_MOUNT" || fail "test volume"
  hdiutil attach "$WORK_DIR/vol.dmg" -nobrowse -mountpoint "$VOLUME_MOUNT" || fail "test volume"
  export AIRSIGN_TEST_VOLUME="$VOLUME_MOUNT"
else
  unset AIRSIGN_TEST_VOLUME
fi
TEST_LOG="$WORK_DIR/tests.log"
# The debug build already compiled the tests, with the same coverage and warning flags.
swift test --skip-build "${DEBUG_ARGS[@]}" ${SWIFT_ARGS[@]+"${SWIFT_ARGS[@]}"} 2>&1 | tee "$TEST_LOG" || fail tests
TEST_COUNT="$(awk '
  /Test run with/ {
    runs++
    if (match($0, /Test run with [0-9]+ tests([[:space:]]|$)/)) {
      count = substr($0, RSTART, RLENGTH)
      sub(/^Test run with /, "", count)
      sub(/ tests.*$/, "", count)
    }
  }
  END { if (runs != 1 || count == "") exit 1; print count }
' "$TEST_LOG")" || fail tests
SKIPPED_TESTS="$(awk '
  match($0, /(^|[[:space:]])(Test|Suite) .* skipped([[:space:][:punct:]]|$)/) {
    name = substr($0, RSTART)
    sub(/^[[:space:]]*/, "", name)
    sub(/ skipped([[:space:][:punct:]].*)?$/, "", name)
    sub(/^Test /, "", name)
    sub(/\(\)$/, "", name)
    if (name == "") exit 1
    print name
  }
' "$TEST_LOG")" || fail "skipped tests"
SKIPPED_SUMMARY="${SKIPPED_TESTS//$'\n'/, }"
echo "tests: $TEST_COUNT run, skipped: ${SKIPPED_SUMMARY:-none}"

echo "==> 3/6 test count"
README_COUNT="$(grep -Eo '[0-9]+ unit tests' "$REPO_ROOT/README.md" | sed 's/ unit tests$//')" || fail "test count"
[[ "$README_COUNT" =~ ^[0-9]+$ && "$TEST_COUNT" == "$README_COUNT" ]] || fail "test count"
while IFS= read -r name; do
  case "$name" in
    "") ;;
    roundTwoOwnerVersusImitatorAUC)
      [[ ! -e "$REPO_ROOT/spikes/airpods-motion/sessions" ]] || fail "skipped tests" ;;
    lockAndUnlockWorkOnAVolumeWithoutExclusiveRename)
      [[ "$WITH_TEST_VOLUME" == 0 ]] || fail "skipped tests" ;;
    *) fail "skipped tests" ;;
  esac
done <<< "$SKIPPED_TESTS"

echo "==> 4/6 coverage"
DEBUG_BIN="$(swift build --show-bin-path "${DEBUG_ARGS[@]}" ${SWIFT_ARGS[@]+"${SWIFT_ARGS[@]}"})" || fail coverage
xcrun llvm-cov report "$DEBUG_BIN/AirSignPackageTests.xctest/Contents/MacOS/AirSignPackageTests" \
  -instr-profile="$DEBUG_BIN/codecov/default.profdata" "$PACKAGE_ROOT/Sources/AirSignCore" \
  > "$WORK_DIR/coverage.txt" || fail coverage
COVERAGE="$(awk '
  $1 == "TOTAL" {
    rows++
    if ($8 !~ /^[0-9]+$/ || $9 !~ /^[0-9]+$/ || $8 <= 0 || $9 > $8) exit 1
    covered = $8 - $9
    printf "%d %d %.1f\n", covered, $8, 100 * covered / $8
  }
  END { if (rows != 1) exit 1 }
' "$WORK_DIR/coverage.txt")" || fail coverage
read -r COVERED TOTAL PERCENT <<< "$COVERAGE"
printf 'coverage: AirSignCore %s/%s lines = %s%% (floor %s%%)\n' "$COVERED" "$TOTAL" "$PERCENT" "$COVERAGE_FLOOR"
awk -v covered="$COVERED" -v total="$TOTAL" -v floor="$COVERAGE_FLOOR" \
  'BEGIN { exit !(100 * covered >= floor * total) }' || fail coverage

echo "==> 5/6 app bundle"
BUNDLE_SWIFT_ARGS="-Xswiftc -warnings-as-errors"
AIRSIGN_SIGN_ID=- AIRSIGN_LAB=0 AIRSIGN_APP="$WORK_DIR/default/AirSign.app" \
  AIRSIGN_SWIFT_ARGS="$BUNDLE_SWIFT_ARGS --scratch-path .build/check-default${AIRSIGN_SWIFT_ARGS:+ $AIRSIGN_SWIFT_ARGS}" \
  scripts/build-app.sh || fail "app bundle"
AIRSIGN_SIGN_ID=- AIRSIGN_LAB=1 AIRSIGN_APP="$WORK_DIR/lab/AirSign.app" \
  AIRSIGN_SWIFT_ARGS="$BUNDLE_SWIFT_ARGS --scratch-path .build/check-lab${AIRSIGN_SWIFT_ARGS:+ $AIRSIGN_SWIFT_ARGS}" \
  scripts/build-app.sh || fail "app bundle"
bundle_strings "$WORK_DIR/default/AirSign.app/Contents/MacOS/AirSign" \
  "$WORK_DIR/default-strings.txt" "$WORK_DIR/default-assembly.txt" || fail "app bundle"
bundle_strings "$WORK_DIR/lab/AirSign.app/Contents/MacOS/AirSign" \
  "$WORK_DIR/lab-strings.txt" "$WORK_DIR/lab-assembly.txt" || fail "app bundle"
for flag in --test-mode --probe --selftest-keychain; do
  if grep -Fq -- "$flag" "$WORK_DIR/default-strings.txt"; then
    fail "app bundle"
  else
    [[ "$?" == 1 ]] || fail "app bundle"
  fi
  grep -Fq -- "$flag" "$WORK_DIR/lab-strings.txt" || fail "app bundle"
done

echo "==> 6/6 machine paths"
MACHINE_PATH_PATTERN='/''Users''/|C:''/airsign-data'
if git -C "$REPO_ROOT" grep -n -a -E "$MACHINE_PATH_PATTERN" -- . ':!docs/superpowers'; then
  fail "machine paths"
else
  [[ "$?" == 1 ]] || fail "machine paths"
fi

cleanup || fail "test volume"
echo "All checks passed."
