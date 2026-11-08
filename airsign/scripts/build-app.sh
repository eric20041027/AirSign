#!/usr/bin/env bash
# Builds build/AirSign.app from the Swift package and signs it with a stable
# Apple Development identity, so the Keychain trusts every rebuild without a prompt.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/AirSign.app
swift build -c release --product AirSign
BIN_DIR="$(swift build -c release --show-bin-path)"

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
echo "Built $APP (signed with: $SIGN_ID)"
