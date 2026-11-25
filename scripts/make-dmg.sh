#!/bin/sh
# Builds build/Tinyproxy.app and packages it as build/Tinyproxy-<version>.dmg,
# with an Applications shortcut for drag-to-install.
set -eu

cd "$(dirname "$0")/.."

./scripts/build-app.sh

APP="build/Tinyproxy.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="build/Tinyproxy-$VERSION.dmg"
STAGE="build/dmg"

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "Tinyproxy" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
rm -rf "$STAGE"

hdiutil verify "$DMG"
echo "Built $DMG"
