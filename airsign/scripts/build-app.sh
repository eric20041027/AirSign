#!/usr/bin/env bash
# Builds build/AirSign.app from the Swift package and signs it with a stable
# Apple Development identity, so the Keychain trusts every rebuild without a prompt.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${AIRSIGN_APP:-build/AirSign.app}"
if [[ "$(basename "$APP")" != *.app ]]; then
  echo "AIRSIGN_APP must end in .app" >&2
  exit 1
fi

EXTRA=()
if [[ "${AIRSIGN_LAB:-0}" == "1" ]]; then
  EXTRA=(-Xswiftc -DAIRSIGN_LAB)
fi
SWIFT_ARGS=()
IFS=' ' read -r -a SWIFT_ARGS <<< "${AIRSIGN_SWIFT_ARGS:-}"
swift build -c release --product AirSign ${EXTRA[@]+"${EXTRA[@]}"} ${SWIFT_ARGS[@]+"${SWIFT_ARGS[@]}"}
BIN_DIR="$(swift build -c release --show-bin-path ${EXTRA[@]+"${EXTRA[@]}"} ${SWIFT_ARGS[@]+"${SWIFT_ARGS[@]}"})"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/AirSign" "$APP/Contents/MacOS/AirSign"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

SIGN_ID="${AIRSIGN_SIGN_ID:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')}"
if [[ -z "$SIGN_ID" ]]; then
  if [[ "${AIRSIGN_ADHOC:-0}" == "1" ]]; then
    echo "warning: ad-hoc signing; the Keychain may ask for your password after each rebuild" >&2
    SIGN_ID="-"
  else
    echo "No Apple Development certificate. Xcode → Settings → Accounts → your Apple ID → Manage Certificates → + → Apple Development." >&2
    exit 1
  fi
fi

codesign --force --sign "$SIGN_ID" --options runtime "$APP"
if [[ "${AIRSIGN_LAB:-0}" == "1" ]]; then
  echo "Built $APP (lab build, signed with: $SIGN_ID)"
else
  echo "Built $APP (signed with: $SIGN_ID)"
fi
