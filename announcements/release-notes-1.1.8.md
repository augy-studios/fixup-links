A fix for the desktop apps: adding a Fix a link widget no longer crashes uwuFix, and uwuFix opens again for anyone it was crashing on at start because of one. The Android app is unchanged: it stays on [1.1.3](https://github.com/augy-studios/fixup-links/releases/tag/android-v1.1.3).

## Download

| Device | File |
|---|---|
| Windows 10 or 11 (x64 or Arm) | `uwufix-1.1.8-setup.exe`, or `uwufix-1.1.8.msi` |
| macOS 12 or newer, Apple silicon | `uwufix-1.1.8-mac-arm64.dmg` |
| macOS 12 or newer, Intel | `uwufix-1.1.8-mac-x64.dmg` |
| Debian, Ubuntu, Mint | `uwufix-1.1.8-amd64.deb` (or `-arm64.deb`) |
| Fedora, openSUSE | `uwufix-1.1.8-x86_64.rpm` (or `-aarch64.rpm`) |
| Any other Linux | `uwufix-1.1.8-x86_64.AppImage` (or `-arm64.AppImage`) |
| Android 7.0 or newer | `uwufix-1.1.3.apk`, from [1.1.3](https://github.com/augy-studios/fixup-links/releases/tag/android-v1.1.3) |

## Updating

**Already have uwuFix on your computer?** It updates itself: restart it when it says 1.1.8 is ready, or pick **Check for updates** in the tray.

**Did uwuFix close as soon as you opened it?** That's the widget crash: download and run 1.1.8's installer below, and it opens again, widget and all.

**Windows**: run the `-setup.exe`. If SmartScreen warns, tap **More info** > **Run anyway**.

**macOS**: open the `.dmg` and drag uwuFix to Applications. The first time, right-click uwuFix > **Open**.

**Linux**: the `.deb` or `.rpm` installs uwuFix in your menu; the AppImage runs from anywhere and updates itself.

Your history and settings stay when you update.

## What's new

### Desktop apps
- **Fix a link widgets work again (Windows)**: adding one from the tray or the command bar crashed uwuFix, and it then crashed each time it started, as it reopened the widget. Now the widget opens, and stays out of the taskbar as it should.
