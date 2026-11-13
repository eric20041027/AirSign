#!/usr/bin/env bash
set -euo pipefail

COVERAGE_FLOOR=85
LAB_FLAGS=(--test-mode --probe --selftest-keychain)

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

without_warnings() {
  local log="$1"
  shift
  "$@" 2>&1 | tee "$log" || return 1
  if grep -Fq 'warning:' "$log"; then
    return 1
  else
    [[ "$?" == 1 ]] || return 1
  fi
}

decode_small_strings() {
  # Keep 16-bit slices separately: awk numbers cannot hold every 64-bit integer.
  awk '
    function hex(s, n, i) {
      n = 0
      for (i = 1; i <= length(s); i++) n = 16 * n + index("0123456789abcdef", tolower(substr(s, i, 1))) - 1
      return n
    }
    ($2 == "mov" || $2 == "movk") && $3 ~ /^[xw][0-9]+,$/ &&
        $4 ~ /^#-?0x[[:xdigit:]]+,?$/ {
      register = substr($3, 2, length($3) - 2)
      width = (substr($3, 1, 1) == "w" ? 2 : 4)
      negative = ($4 ~ /^#-/)
      digits = $4
      sub(/^#-?0x/, "", digits); sub(/,$/, "", digits)
      if ($2 == "mov") {
        digits = "0000000000000000" digits
        carry = negative
        for (i = 0; i < 4; i++) {
          n = 0
          if (i < width) {
            n = hex(substr(digits, length(digits) - 4 * i - 3, 4))
            if (negative) {
              n = 65535 - n + carry
              carry = (n >= 65536)
              n %= 65536
            }
          }
          word[register, i] = n
        }
        have[register] = 1
      } else {
        shift = ($5 == "lsl" ? substr($6, 2) + 0 : 0)
        if (!have[register] || negative || length(digits) > 4 ||
            shift % 16 != 0 || shift < 0 || shift >= 16 * width) next
        word[register, shift / 16] = hex(digits)
        # A write to wN also clears the upper half of xN.
        if (width == 2) word[register, 2] = word[register, 3] = 0
      }
      # Every update is a candidate, independent of other registers/instructions.
      for (i = 0; i < 4; i++) {
        n = word[register, i]
        printf "%c%c", n % 256, int(n / 256)
      }
      printf "\n"
    }
  ' "$@" | strings
}

decoder_case() {
  local candidates signature
  candidates="$(decode_small_strings)" || return 1
  for signature in "$@"; do
    grep -Fxq -- "$signature" <<< "$candidates" || return 1
  done
}

check_decoder() {
  # llvm-objdump --disassemble --no-show-raw-insn format on arm64 macOS.
  # Load the second half of the Swift string before its first eight bytes.
  decoder_case "${LAB_FLAGS[0]:0:8}" <<'ASM' || return 1
10000630c:     	mov	x1, #0x646f             ; =25711
100006310:     	movk	x1, #0x65, lsl #16
100006314:     	movk	x1, #0xeb00, lsl #48
100006318:     	mov	x0, #0x2d2d             ; =11565
10000631c:     	movk	x0, #0x6574, lsl #16
100006320:     	movk	x0, #0x7473, lsl #32
100006324:     	movk	x0, #0x6d2d, lsl #48
ASM
  # An unrelated instruction must not discard the partial value.
  decoder_case "${LAB_FLAGS[1]:0:8}" <<'ASM' || return 1
10000630c:     	mov	x0, #0x2d2d             ; =11565
100006310:     	add	x8, x8, #0xf
100006314:     	movk	x0, #0x7270, lsl #16
100006318:     	movk	x0, #0x626f, lsl #32
10000631c:     	movk	x0, #0x65, lsl #48
ASM
  # Both registers must survive interleaved updates.
  decoder_case "${LAB_FLAGS[0]:0:8}" "${LAB_FLAGS[1]:0:8}" <<'ASM' || return 1
10000630c:     	mov	x0, #0x2d2d             ; =11565
100006310:     	mov	x1, #0x2d2d             ; =11565
100006314:     	movk	x0, #0x6574, lsl #16
100006318:     	movk	x1, #0x7270, lsl #16
10000631c:     	movk	x0, #0x7473, lsl #32
100006320:     	movk	x1, #0x626f, lsl #32
100006324:     	movk	x0, #0x6d2d, lsl #48
100006328:     	movk	x1, #0x65, lsl #48
ASM
  decoder_case main <<'ASM' || return 1
100001930:     	mov	w1, #0x616d             ; =24941
100001934:     	movk	w1, #0x6e69, lsl #16
ASM
}

bundle_strings() {
  local binary="$1" output="$2" assembly="$3"
  strings "$binary" > "$output" || return 1
  # Optimized arm64 Swift small strings can live in mov/movk immediates.
  xcrun llvm-objdump --disassemble --no-show-raw-insn "$binary" > "$assembly" || return 1
  decode_small_strings "$assembly" >> "$output"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/airsign-check.XXXXXX")" || fail build

SWIFT_ARGS=()
IFS=' ' read -r -a SWIFT_ARGS <<< "${AIRSIGN_SWIFT_ARGS:-}"
# Covers Package.swift without the deprecation warning emitted by -Xmanifest.
DEBUG_ARGS=(--enable-code-coverage -Xswiftc -warnings-as-errors -Xbuild-tools-swiftc -warnings-as-errors)

echo "==> 1/6 build"
without_warnings "$WORK_DIR/debug-build.log" \
  swift build --build-tests "${DEBUG_ARGS[@]}" ${SWIFT_ARGS[@]+"${SWIFT_ARGS[@]}"} || fail build
without_warnings "$WORK_DIR/default-build.log" \
  swift build -c release --product AirSign -Xswiftc -warnings-as-errors -Xbuild-tools-swiftc -warnings-as-errors \
  --scratch-path .build/check-default ${SWIFT_ARGS[@]+"${SWIFT_ARGS[@]}"} || fail build
without_warnings "$WORK_DIR/lab-build.log" \
  swift build -c release --product AirSign -Xswiftc -DAIRSIGN_LAB -Xswiftc -warnings-as-errors -Xbuild-tools-swiftc -warnings-as-errors \
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
  /^[^[:alnum:]]*Test run with [0-9]+ tests? in [0-9]+ suites? passed after [0-9]+(\.[0-9]+)? seconds\.$/ {
    runs++
    count = $0
    sub(/^[^[:alnum:]]*Test run with /, "", count)
    sub(/ tests? in .*$/, "", count)
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
check_decoder || fail "app bundle"
BUNDLE_SWIFT_ARGS="-Xswiftc -warnings-as-errors -Xbuild-tools-swiftc -warnings-as-errors"
AIRSIGN_SIGN_ID=- AIRSIGN_LAB=0 AIRSIGN_APP="$WORK_DIR/default/AirSign.app" \
  AIRSIGN_SWIFT_ARGS="$BUNDLE_SWIFT_ARGS --scratch-path .build/check-default${AIRSIGN_SWIFT_ARGS:+ $AIRSIGN_SWIFT_ARGS}" \
  without_warnings "$WORK_DIR/default-bundle.log" scripts/build-app.sh || fail "app bundle"
AIRSIGN_SIGN_ID=- AIRSIGN_LAB=1 AIRSIGN_APP="$WORK_DIR/lab/AirSign.app" \
  AIRSIGN_SWIFT_ARGS="$BUNDLE_SWIFT_ARGS --scratch-path .build/check-lab${AIRSIGN_SWIFT_ARGS:+ $AIRSIGN_SWIFT_ARGS}" \
  without_warnings "$WORK_DIR/lab-bundle.log" scripts/build-app.sh || fail "app bundle"
bundle_strings "$WORK_DIR/default/AirSign.app/Contents/MacOS/AirSign" \
  "$WORK_DIR/default-strings.txt" "$WORK_DIR/default-assembly.txt" || fail "app bundle"
bundle_strings "$WORK_DIR/lab/AirSign.app/Contents/MacOS/AirSign" \
  "$WORK_DIR/lab-strings.txt" "$WORK_DIR/lab-assembly.txt" || fail "app bundle"
for flag in "${LAB_FLAGS[@]}"; do
  # The prefix also matches a complete flag (or its prefix) in plain strings.
  signature="${flag:0:8}"
  if grep -Fq -- "$signature" "$WORK_DIR/default-strings.txt"; then
    fail "app bundle"
  else
    [[ "$?" == 1 ]] || fail "app bundle"
  fi
  grep -Fq -- "$signature" "$WORK_DIR/lab-strings.txt" || fail "app bundle"
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
