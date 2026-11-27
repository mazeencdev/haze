#!/bin/bash
# Builds Haze.app next to this script.
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP=Haze.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Haze "$APP/Contents/MacOS/Haze"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ ! -f Resources/AppIcon.icns ] || [ Resources/make_icon.swift -nt Resources/AppIcon.icns ]; then
  TMP=$(mktemp -d)
  mkdir -p Logo
  swift Resources/make_icon.swift Logo
  mkdir "$TMP/AppIcon.iconset"
  for s in 16 32 128 256 512; do
    sips -z $s $s Logo/haze-icon.png --out "$TMP/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) Logo/haze-icon.png --out "$TMP/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$TMP/AppIcon.iconset" -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP"
echo "Built $(pwd)/$APP"
