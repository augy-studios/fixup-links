A small fix for Windows: the tray menu now closes when you click away from it, and takes the tray's overflow flyout with it, instead of staying open. The Android app is unchanged: it stays on [1.1.3](https://github.com/augy-studios/fixup-links/releases/tag/android-v1.1.3).

## Download

| Device | File |
|---|---|
| Windows 10 or 11 (x64 or Arm) | `uwufix-1.1.6-setup.exe`, or `uwufix-1.1.6.msi` |
| macOS 12 or newer, Apple silicon | `uwufix-1.1.6-mac-arm64.dmg` |
| macOS 12 or newer, Intel | `uwufix-1.1.6-mac-x64.dmg` |
| Debian, Ubuntu, Mint | `uwufix-1.1.6-amd64.deb` (or `-arm64.deb`) |
| Fedora, openSUSE | `uwufix-1.1.6-x86_64.rpm` (or `-aarch64.rpm`) |
| Any other Linux | `uwufix-1.1.6-x86_64.AppImage` (or `-arm64.AppImage`) |
| Android 7.0 or newer | `uwufix-1.1.3.apk`, from [1.1.3](https://github.com/augy-studios/fixup-links/releases/tag/android-v1.1.3) |

## Updating

**Already have uwuFix on your computer?** It updates itself: restart it when it says 1.1.6 is ready, or pick **Check for updates** in the tray.

**Windows**: run the `-setup.exe`. If SmartScreen warns, tap **More info** > **Run anyway**.

**macOS**: open the `.dmg` and drag uwuFix to Applications. The first time, right-click uwuFix > **Open**.

**Linux**: the `.deb` or `.rpm` installs uwuFix in your menu; the AppImage runs from anywhere and updates itself.

Your history and settings stay when you update.

## What's new

### Desktop apps
- **The tray menu closes when you click away (Windows)**: right-click uwuFix in the tray, then click anywhere else, and the menu closes, along with the tray's overflow flyout if uwuFix was in it. A hidden window stays hidden.
