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
OUT="$(realpath -m "$2")"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(pwd)"
case "$(uname -m)" in
  x86_64) DEB=amd64; RPM=x86_64; AI=x86_64; BUNDLE=build/linux/x64/release/bundle ;;
  aarch64|arm64) DEB=arm64; RPM=aarch64; AI=aarch64; BUNDLE=build/linux/arm64/release/bundle ;;
  *) echo "unknown processor $(uname -m)"; exit 1 ;;
esac
AINAME=$([ "$AI" = aarch64 ] && echo arm64 || echo x86_64)
mkdir -p "$OUT"
WORK="$(mktemp -d)"

# ---- the files, as installed ----
STAGE="$WORK/root"
mkdir -p "$STAGE/opt/uwuFix" "$STAGE/usr/bin" "$STAGE/usr/share/applications" "$STAGE/usr/share/icons/hicolor/512x512/apps"
cp -r "$ROOT/$BUNDLE/." "$STAGE/opt/uwuFix/"
ln -s /opt/uwuFix/uwufix "$STAGE/usr/bin/uwufix"
cp "$HERE/uwufix.desktop" "$STAGE/usr/share/applications/uwufix.desktop"
cp "$ROOT/assets/desktop/icon.png" "$STAGE/usr/share/icons/hicolor/512x512/apps/uwufix.png"

# ---- .deb ----
DEBROOT="$WORK/deb"
cp -a "$STAGE" "$DEBROOT"
mkdir -p "$DEBROOT/DEBIAN"
SIZE=$(du -sk "$DEBROOT/opt" | cut -f1)
cat > "$DEBROOT/DEBIAN/control" <<EOF
Package: uwufix
Version: $VERSION
Section: utils
Priority: optional
Architecture: $DEB
Maintainer: Augy <noreply@uwuapps.org>
Installed-Size: $SIZE
Depends: libgtk-3-0 | libgtk-3-0t64, libayatana-appindicator3-1 | libappindicator3-1
Homepage: https://fixup.uwuapps.org
Description: Clean links, strip trackers and fix embeds
 uwuFix cleans tracking parameters out of links and swaps in embed-friendly
 domains, so links preview properly in Discord, Telegram and more.
EOF
cat > "$DEBROOT/DEBIAN/postinst" <<'EOF'
#!/bin/sh
update-desktop-database -q /usr/share/applications 2>/dev/null || true
gtk-update-icon-cache -q /usr/share/icons/hicolor 2>/dev/null || true
EOF
chmod 755 "$DEBROOT/DEBIAN/postinst"
dpkg-deb --root-owner-group --build "$DEBROOT" "$OUT/uwufix-$VERSION-$DEB.deb"

# ---- .rpm ----
if command -v rpmbuild >/dev/null 2>&1; then
  RPMTOP="$WORK/rpm"
  mkdir -p "$RPMTOP/BUILD" "$RPMTOP/RPMS" "$RPMTOP/SPECS"
  cat > "$RPMTOP/SPECS/uwufix.spec" <<EOF
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
  rpmbuild --define "_topdir $RPMTOP" --target "$RPM" -bb "$RPMTOP/SPECS/uwufix.spec"
  cp "$RPMTOP"/RPMS/*/uwufix-*.rpm "$OUT/uwufix-$VERSION-$RPM.rpm"
fi

# ---- AppImage ----
APPDIR="$WORK/uwuFix.AppDir"
mkdir -p "$APPDIR/usr"
cp -r "$ROOT/$BUNDLE/." "$APPDIR/usr/"
cp "$HERE/uwufix.desktop" "$APPDIR/uwufix.desktop"
sed -i 's#^Exec=.*#Exec=uwufix %u#' "$APPDIR/uwufix.desktop"
cp "$ROOT/assets/desktop/icon.png" "$APPDIR/uwufix.png"
cat > "$APPDIR/AppRun" <<'EOF'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/uwufix" "$@"
EOF
chmod +x "$APPDIR/AppRun"
TOOL="$WORK/appimagetool"
curl -fsSL -o "$TOOL" "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$AI.AppImage"
chmod +x "$TOOL"
ARCH="$AI" "$TOOL" --appimage-extract-and-run "$APPDIR" "$OUT/uwufix-$VERSION-$AINAME.AppImage"

rm -rf "$WORK"
ls -la "$OUT"
