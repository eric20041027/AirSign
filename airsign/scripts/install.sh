#!/usr/bin/env bash
# Installs AirSign.app into ~/Applications and registers its Finder Services.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build-app.sh

mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/AirSign.app"
cp -R build/AirSign.app "$HOME/Applications/"

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$HOME/Applications/AirSign.app"
/System/Library/CoreServices/pbs -update

echo "Installed AirSign.app to ~/Applications and updated Services."
