#!/bin/sh
# Builds a universal (Apple silicon + Intel) release binary and wraps it in
# build/Tinyproxy.app (ad-hoc signed).
set -eu

cd "$(dirname "$0")/.."

# The "x86_64 architecture is deprecated for your deployment target" warning
# refers to the host macOS, not the binary: both slices still target macOS 13.
BUILD="swift build -c release --arch arm64 --arch x86_64"
$BUILD
BIN="$($BUILD --show-bin-path)/TinyproxyGUI"

APP="build/Tinyproxy.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TinyproxyGUI"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"

echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/TinyproxyGUI"))"
