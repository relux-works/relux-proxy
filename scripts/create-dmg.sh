#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-0.1.0-dev}"
VERSION="${VERSION#v}"
APP="$ROOT/dist/ReluxProxy.app"
DMG="$ROOT/dist/ReluxProxy-v$VERSION-universal.dmg"
STAGE="$ROOT/.build/dmg-root"

if [[ ! -d "$APP" ]]; then
    echo "error: $APP does not exist; run scripts/build-app.sh first" >&2
    exit 1
fi

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Relux Proxy" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
echo "Built $DMG"
