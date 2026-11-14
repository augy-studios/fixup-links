#!/bin/sh
# uwuFix's Mac files (docs/flutter-desktop-app-spec.md §10), from `flutter build macos --release`'s
# universal uwuFix.app, one set per processor (ditto --arch keeps only that one's code):
#
#   uwufix-<v>-mac-arm64.dmg, -mac-x64.dmg   drag to Applications
#   uwufix-<v>-mac-arm64.zip, -mac-x64.zip   what the app's updater downloads (latest-mac.yml)
#
# Each .app is ad-hoc signed (codesign -s -): there's no Developer ID, so the first open needs
# right-click > Open (flutter/README.md says so).
#
#   installers/macos/package.sh <version> <out folder>      (from flutter/)
set -eu
VERSION="$1"
OUT="$2"
APP="build/macos/Build/Products/Release/uwuFix.app"
mkdir -p "$OUT"
for ARCH in arm64 x64; do
  CPU=$([ "$ARCH" = x64 ] && echo x86_64 || echo arm64)
  WORK="$(mktemp -d)"
  ditto --arch "$CPU" "$APP" "$WORK/uwuFix.app"
  codesign --force --deep -s - "$WORK/uwuFix.app"
  ditto -c -k --sequesterRsrc --keepParent "$WORK/uwuFix.app" "$OUT/uwufix-$VERSION-mac-$ARCH.zip"
  ln -s /Applications "$WORK/Applications"
  hdiutil create -volname "uwuFix $VERSION" -srcfolder "$WORK" -ov -format UDZO "$OUT/uwufix-$VERSION-mac-$ARCH.dmg"
  rm -rf "$WORK"
done
ls -la "$OUT"
