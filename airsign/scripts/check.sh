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
  local whole=0
  if [[ "${1:-}" == --whole ]]; then
    whole=1
    shift
  fi
  # Keep 16-bit slices separately: awk numbers cannot hold every 64-bit integer.
  awk -v whole="$whole" '
    function hex(s, n, i) {
      n = 0
      for (i = 1; i <= length(s); i++) n = 16 * n + index("0123456789abcdef", tolower(substr(s, i, 1))) - 1
      return n
    }
    function whole_string(count, i, n, byte, value) {
      if (!have[0] || !have[1]) return
      count = int(word[1, 3] / 256) - 224
      if (count < 1 || count > 15) return
      for (i = 0; i < 15; i++) {
        n = word[int(i / 8), int((i % 8) / 2)]
        byte = (i % 2 == 0 ? n % 256 : int(n / 256))
        if (i < count) {
          if (byte < 32 || byte > 126) return
          value = value sprintf("%c", byte)
        } else if (byte != 0) return
      }
      print value
    }
    # The lab binary passes the two string words in x0/x1 to contains().
    whole && ($2 == "bl" || $2 == "blr") {
      whole_string()
      have[0] = have[1] = 0
      next
    }
    whole && ($0 ~ /<.*>:$/ || $2 ~ /^(b|ret|cbz|cbnz|tbz|tbnz)/) {
      have[0] = have[1] = 0
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
            shift % 16 != 0 || shift < 0 || shift >= 16 * width) {
          if (whole) have[register] = 0
          next
        }
        word[register, shift / 16] = hex(digits)
        # A write to wN also clears the upper half of xN.
        if (width == 2) word[register, 2] = word[register, 3] = 0
      }
      if (whole) next
      # Every update is a candidate, independent of other registers/instructions.
      for (i = 0; i < 4; i++) {
        n = word[register, i]
        printf "%c%c", n % 256, int(n / 256)
      }
      printf "\n"
      next
    }
    whole {
      # Discard argument words referenced by instructions we do not interpret.
      if ($0 ~ /(^|[^[:alnum:]_])[xw]0([^[:alnum:]_]|$)/) have[0] = 0
      if ($0 ~ /(^|[^[:alnum:]_])[xw]1([^[:alnum:]_]|$)/) have[1] = 0
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

whole_decoder_case() {
  local candidate
  candidate="$(decode_small_strings --whole)" || return 1
  [[ "$candidate" == "$1" ]]
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
  # Whole strings require both words, including zero padding and the length byte.
  whole_decoder_case "${LAB_FLAGS[0]}" <<'ASM' || return 1
10000630c:     	mov	x1, #0x646f
100006310:     	movk	x1, #0x65, lsl #16
100006314:     	movk	x1, #0xeb00, lsl #48
100006318:     	mov	x0, #0x2d2d
10000631c:     	movk	x0, #0x6574, lsl #16
100006320:     	movk	x0, #0x7473, lsl #32
100006324:     	movk	x0, #0x6d2d, lsl #48
100006328:     	bl	0x100003dd8
ASM
  # The same eight-byte prefix with a misspelt suffix must decode as that spelling.
  whole_decoder_case --test-mdoe <<'ASM' || return 1
10000630c:     	mov	x0, #0x2d2d
100006310:     	movk	x0, #0x6574, lsl #16
100006314:     	movk	x0, #0x7473, lsl #32
100006318:     	movk	x0, #0x6d2d, lsl #48
10000631c:     	mov	x1, #0x6f64
100006320:     	movk	x1, #0x65, lsl #16
100006324:     	movk	x1, #0xeb00, lsl #48
100006328:     	bl	0x100003dd8
ASM
  # The compiler loads --probe with a zero-padded x0 and a negative mov into x1.
  whole_decoder_case "${LAB_FLAGS[1]}" <<'ASM' || return 1
100001cd0:     	mov	x0, #0x2d2d
100001cd4:     	movk	x0, #0x7270, lsl #16
100001cd8:     	movk	x0, #0x626f, lsl #32
100001cdc:     	movk	x0, #0x65, lsl #48
100001ce0:     	mov	x1, #-0x1900000000000000
100001ce4:     	mov	x2, x19
100001ce8:     	bl	0x100003dd8
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
SKIPPED_TESTS="$(awk -v expected="$TEST_COUNT" '
  # XCTest reports its empty run before Swift Testing.
  /^Test Suite .* (started|passed|failed) at / { next }
  /^[^[:alnum:]]*(Test|Suite) / {
    outcome = $0
    sub(/^[^[:alnum:]]*/, "", outcome)
    if (outcome ~ /^Test run / || outcome ~ / started\.$/) next
    if (outcome ~ /^(Test|Suite) .+ passed after [0-9]+(\.[0-9]+)? seconds\.$/) {
      # A parameterized function has one result, with its case count before "passed".
      if (outcome ~ /^Test / && outcome !~ /^Test case /) passed++
      else if (outcome ~ /^Test case /) invalid = 1
      next
    }
    if (outcome ~ /^Test .+ skipped([[:space:][:punct:]]|$)/) {
      name = outcome
      sub(/ skipped([[:space:][:punct:]].*)?$/, "", name)
      sub(/^Test /, "", name)
      sub(/\(\)$/, "", name)
      if (name == "" || ++seen[name] > 1) invalid = 1
      skipped++
      print name
      next
    }
    # Cancelled tests and any unfamiliar outcome fail closed, including suite skips.
    invalid = 1
  }
  END { if (invalid || passed + skipped != expected) exit 1 }
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
strings "$WORK_DIR/lab/AirSign.app/Contents/MacOS/AirSign" > "$WORK_DIR/lab-strings.txt" || fail "app bundle"
xcrun llvm-objdump --disassemble --no-show-raw-insn "$WORK_DIR/lab/AirSign.app/Contents/MacOS/AirSign" \
  > "$WORK_DIR/lab-assembly.txt" || fail "app bundle"
decode_small_strings --whole "$WORK_DIR/lab-assembly.txt" > "$WORK_DIR/lab-small-strings.txt" || fail "app bundle"
for flag in "${LAB_FLAGS[@]}"; do
  # The prefix also matches a complete flag (or its prefix) in plain strings.
  signature="${flag:0:8}"
  if grep -Fq -- "$signature" "$WORK_DIR/default-strings.txt"; then
    fail "app bundle"
  else
    [[ "$?" == 1 ]] || fail "app bundle"
  fi
  case "$flag" in
    --selftest-keychain) grep -Fxq -- "$flag" "$WORK_DIR/lab-strings.txt" || fail "app bundle" ;;
    *) grep -Fxq -- "$flag" "$WORK_DIR/lab-small-strings.txt" || fail "app bundle" ;;
  esac
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
