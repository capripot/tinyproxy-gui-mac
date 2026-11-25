#!/bin/sh
# Regenerates Resources/AppIcon.icns from Resources/AppIcon.svg and
# Resources/StatusIcon.tiff from Resources/StatusIcon.svg (needs `brew install librsvg`).
set -eu

cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    rsvg-convert -w $size -h $size Resources/AppIcon.svg -o "$ICONSET/icon_${size}x${size}.png"
    rsvg-convert -w $((size * 2)) -h $((size * 2)) Resources/AppIcon.svg -o "$ICONSET/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "Wrote Resources/AppIcon.icns"

# Menu bar icon: 24x18pt (the SVG is 4:3), with 1x and 2x representations in one TIFF.
rsvg-convert -w 24 -h 18 Resources/StatusIcon.svg -o "$WORK/status.png"
rsvg-convert -w 48 -h 36 Resources/StatusIcon.svg -o "$WORK/status@2x.png"
tiffutil -cathidpicheck "$WORK/status.png" "$WORK/status@2x.png" -out Resources/StatusIcon.tiff
echo "Wrote Resources/StatusIcon.tiff"

rm -rf "$WORK"
