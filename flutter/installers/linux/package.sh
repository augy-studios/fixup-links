#!/bin/sh
# uwuFix's Linux packages (docs/flutter-desktop-app-spec.md §10), from `flutter build linux
# --release`'s bundle, for this computer's processor (each is built on its own: x64 and arm64):
#
#   uwufix-<v>-amd64.deb / -arm64.deb          Debian, Ubuntu, Mint, Raspberry Pi OS
#   uwufix-<v>-x86_64.rpm / -aarch64.rpm       Fedora, openSUSE
#   uwufix-<v>-x86_64.AppImage / -arm64.AppImage   anything else; updates itself
#
# The .deb and .rpm put the bundle in /opt/uwuFix/, a uwufix command on the PATH, the menu entry
# (with the uwu:// scheme) and the icon. The AppImage carries the same entry and icon at its root.
#
#   installers/linux/package.sh <version> <out folder>      (from flutter/)
set -eu
VERSION="$1"
OUT_FOLDER="$(realpath -m "$2")"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(pwd)"
# Each package format's own name for this computer's processor, and where Flutter built for it.
case "$(uname -m)" in
  x86_64)
    DEB_ARCHITECTURE=amd64
    RPM_ARCHITECTURE=x86_64
    APPIMAGE_ARCHITECTURE=x86_64
    BUNDLE=build/linux/x64/release/bundle
    ;;
  aarch64|arm64)
    DEB_ARCHITECTURE=arm64
    RPM_ARCHITECTURE=aarch64
    APPIMAGE_ARCHITECTURE=aarch64
    BUNDLE=build/linux/arm64/release/bundle
    ;;
  *)
    echo "unknown processor $(uname -m)"
    exit 1
    ;;
esac
# The AppImage's file name says arm64 rather than aarch64.
if [ "$APPIMAGE_ARCHITECTURE" = aarch64 ]; then
  APPIMAGE_FILE_ARCHITECTURE=arm64
else
  APPIMAGE_FILE_ARCHITECTURE=x86_64
fi
mkdir -p "$OUT_FOLDER"
WORK="$(mktemp -d)"

# ---- the files, as installed ----
STAGE="$WORK/root"
mkdir -p "$STAGE/opt/uwuFix" "$STAGE/usr/bin" "$STAGE/usr/share/applications" "$STAGE/usr/share/icons/hicolor/512x512/apps"
cp -r "$ROOT/$BUNDLE/." "$STAGE/opt/uwuFix/"
ln -s /opt/uwuFix/uwufix "$STAGE/usr/bin/uwufix"
cp "$HERE/uwufix.desktop" "$STAGE/usr/share/applications/uwufix.desktop"
cp "$ROOT/assets/desktop/icon.png" "$STAGE/usr/share/icons/hicolor/512x512/apps/uwufix.png"

# ---- .deb ----
DEB_ROOT="$WORK/deb"
cp -a "$STAGE" "$DEB_ROOT"
mkdir -p "$DEB_ROOT/DEBIAN"
INSTALLED_SIZE=$(du -sk "$DEB_ROOT/opt" | cut -f1)
cat > "$DEB_ROOT/DEBIAN/control" <<EOF
Package: uwufix
Version: $VERSION
Section: utils
Priority: optional
Architecture: $DEB_ARCHITECTURE
Maintainer: Augy <noreply@uwuapps.org>
Installed-Size: $INSTALLED_SIZE
Depends: libgtk-3-0 | libgtk-3-0t64, libayatana-appindicator3-1 | libappindicator3-1
Homepage: https://fixup.uwuapps.org
Description: Clean links, strip trackers and fix embeds
 uwuFix cleans tracking parameters out of links and swaps in embed-friendly
 domains, so links preview properly in Discord, Telegram and more.
EOF
cat > "$DEB_ROOT/DEBIAN/postinst" <<'EOF'
#!/bin/sh
update-desktop-database -q /usr/share/applications 2>/dev/null || true
gtk-update-icon-cache -q /usr/share/icons/hicolor 2>/dev/null || true
EOF
chmod 755 "$DEB_ROOT/DEBIAN/postinst"
dpkg-deb --root-owner-group --build "$DEB_ROOT" "$OUT_FOLDER/uwufix-$VERSION-$DEB_ARCHITECTURE.deb"

# ---- .rpm ----
if command -v rpmbuild >/dev/null 2>&1; then
  RPM_TOP_FOLDER="$WORK/rpm"
  mkdir -p "$RPM_TOP_FOLDER/BUILD" "$RPM_TOP_FOLDER/RPMS" "$RPM_TOP_FOLDER/SPECS"
  cat > "$RPM_TOP_FOLDER/SPECS/uwufix.spec" <<EOF
Name: uwufix
Version: $VERSION
Release: 1
Summary: Clean links, strip trackers and fix embeds
License: MIT
URL: https://fixup.uwuapps.org
Requires: gtk3
AutoReqProv: no
%define _build_id_links none
%define __strip /bin/true
%description
uwuFix cleans tracking parameters out of links and swaps in embed-friendly domains.
%install
cp -a $STAGE/. %{buildroot}/
%files
/opt/uwuFix
/usr/bin/uwufix
/usr/share/applications/uwufix.desktop
/usr/share/icons/hicolor/512x512/apps/uwufix.png
%post
update-desktop-database -q /usr/share/applications 2>/dev/null || true
EOF
  rpmbuild --define "_topdir $RPM_TOP_FOLDER" --target "$RPM_ARCHITECTURE" -bb "$RPM_TOP_FOLDER/SPECS/uwufix.spec"
  cp "$RPM_TOP_FOLDER"/RPMS/*/uwufix-*.rpm "$OUT_FOLDER/uwufix-$VERSION-$RPM_ARCHITECTURE.rpm"
fi

# ---- AppImage ----
APP_FOLDER="$WORK/uwuFix.AppDir"
mkdir -p "$APP_FOLDER/usr"
cp -r "$ROOT/$BUNDLE/." "$APP_FOLDER/usr/"
cp "$HERE/uwufix.desktop" "$APP_FOLDER/uwufix.desktop"
sed -i 's#^Exec=.*#Exec=uwufix %u#' "$APP_FOLDER/uwufix.desktop"
cp "$ROOT/assets/desktop/icon.png" "$APP_FOLDER/uwufix.png"
cat > "$APP_FOLDER/AppRun" <<'EOF'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/uwufix" "$@"
EOF
chmod +x "$APP_FOLDER/AppRun"
APPIMAGE_TOOL="$WORK/appimagetool"
curl -fsSL -o "$APPIMAGE_TOOL" "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$APPIMAGE_ARCHITECTURE.AppImage"
chmod +x "$APPIMAGE_TOOL"
# appimagetool reads the processor from ARCH.
ARCH="$APPIMAGE_ARCHITECTURE" "$APPIMAGE_TOOL" --appimage-extract-and-run "$APP_FOLDER" "$OUT_FOLDER/uwufix-$VERSION-$APPIMAGE_FILE_ARCHITECTURE.AppImage"

rm -rf "$WORK"
ls -la "$OUT_FOLDER"
