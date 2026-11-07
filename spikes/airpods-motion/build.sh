#!/usr/bin/env bash
# Builds the throwaway AirPods motion spike into build/AirPodsMotion.app (ad-hoc signed, local use only).
set -euo pipefail
cd "$(dirname "$0")"

APP=build/AirPodsMotion.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 Sources/main.swift -o "$APP/Contents/MacOS/AirPodsMotion"
cp Info.plist "$APP/Contents/Info.plist"
cp web/index.html "$APP/Contents/Resources/index.html"
codesign --force --sign - "$APP"
echo "Built $APP — run: open $APP"
