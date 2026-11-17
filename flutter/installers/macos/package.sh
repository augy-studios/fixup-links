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
OUT_FOLDER="$2"
APP="build/macos/Build/Products/Release/uwuFix.app"
mkdir -p "$OUT_FOLDER"
for ARCHITECTURE in arm64 x64; do
  # ditto's name for the processor: x86_64 for x64.
  if [ "$ARCHITECTURE" = x64 ]; then
    DITTO_ARCHITECTURE=x86_64
  else
    DITTO_ARCHITECTURE=arm64
  fi
  WORK="$(mktemp -d)"
  ditto --arch "$DITTO_ARCHITECTURE" "$APP" "$WORK/uwuFix.app"
  codesign --force --deep -s - "$WORK/uwuFix.app"
  ditto -c -k --sequesterRsrc --keepParent "$WORK/uwuFix.app" "$OUT_FOLDER/uwufix-$VERSION-mac-$ARCHITECTURE.zip"
  ln -s /Applications "$WORK/Applications"
  hdiutil create -volname "uwuFix $VERSION" -srcfolder "$WORK" -ov -format UDZO "$OUT_FOLDER/uwufix-$VERSION-mac-$ARCHITECTURE.dmg"
  rm -rf "$WORK"
done
ls -la "$OUT_FOLDER"
