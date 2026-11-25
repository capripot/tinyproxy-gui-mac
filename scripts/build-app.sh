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
cp Resources/AppIcon.icns Resources/StatusIcon.tiff "$APP/Contents/Resources/"

# Record the commit the app was built from; the About panel shows it after the version.
# "-dirty" marks a build with uncommitted changes. Skipped when not in a git checkout.
if COMMIT="$(git rev-parse --short HEAD 2>/dev/null)"; then
    git diff --quiet HEAD -- 2>/dev/null || COMMIT="$COMMIT-dirty"
    /usr/libexec/PlistBuddy -c "Add :TinyproxyGUIGitCommit string $COMMIT" "$APP/Contents/Info.plist"
fi

codesign --force --sign - "$APP"

echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/TinyproxyGUI"))"
