# Desktop apps in Flutter: spec for Windows, macOS and Linux from the phone app's code

Windows, macOS and Linux apps built from the **same Flutter project and the same Dart features** as
the Android app (`flutter-android-app-spec.md`), plus a desktop layer for what a computer has and a
phone doesn't: a multi-pane shell, a tray, its own title bar with a command bar, native context
menus, several windows, notifications without a push service, starting at sign-in, URL schemes, a
Jump List and a Dock, and self-updating installers. Every desktop feature to build is listed in
`desktop-features-spec.md`; this document is how.

The rule that keeps it maintainable: **the feature widgets and logic are shared, the platform is a
host.** Desktop code never forks a feature's business logic or data state. It answers the same
bridge calls the phone's native code answers (`Native.call`, `Native.has`, `Native.on`), arranges
shared views into a desktop-native multi-pane shell, adapts sheets and menus for mouse and keyboard,
and owns only what has no phone equivalent.

---

## 0. Decide first

| Decision | Example | Why it matters |
|---|---|---|
| Executable and bundle name | `Example App` (`Example App.exe`, `Example App.app`) | Shortcuts, the Jump List, the scheme handler and an older app's updater all point at it. Keep it forever |
| App id | `org.example.app` | The macOS bundle id, the Windows AppUserModelID, the Linux application id. The same as the Android id |
| Settings folder | `%APPDATA%\Example App`, `~/Library/Application Support/Example App`, `~/.config/Example App` | Where the desktop settings file lives; the same folder an earlier desktop app used, so it's read in place |
| Platforms and processors | Windows x64 + Arm64, macOS arm64 + x64, Linux x64 + arm64 | Each builds on its own OS and processor (§11) |
| Installers | NSIS `.exe` + WiX `.msi`; `.dmg` + `.zip`; `.deb`, `.rpm`, AppImage | §10 |
| Map engine | the phone's native map SDK has no desktop build | A WebView running the same engine's JS build (§8) |
| Code signing | none, or a certificate later | Unsigned apps warn once; macOS's own updater needs a Developer ID, so the app swaps its own bundle (§9) |

---

## 1. One project, every platform

```text
<app>/
  pubspec.yaml            one set of packages; desktop-only ones are harmless on Android
  lib/main.dart           start-up: decides phone or desktop, then the same runApp
  lib/desktop/            the desktop layer (this document)
    desktop.dart          start-up, the window, the tray, single instance, links, start at sign-in
    host.dart             the bridge host answering Native.call on the desktop (§3)
    chrome.dart           the title bar, command bar, navigation rail, and multi-pane shell (§2.3)
    adaptive.dart         desktop equivalents for sheets, context menus, and scroll physics (§2.4)
    menubar.dart          native macOS PlatformMenuBar and global desktop keyboard shortcuts (§2.5)
    welcome.dart          the welcome window's screen
    splash.dart           the update window's screen
    updater.dart          finding, downloading, verifying and installing updates (§9)
    widgets_window.dart   a desktop widget's screen, run in its own engine (§6)
    glance.dart           the tray countdown, Jump List, thumbnail buttons, Dock (§7)
    notify.dart           system notifications and their clicks (§5)
    alerts_poll.dart      polling what push would have delivered (§5)
    location.dart         location where the system can't give it (§4)
    screenshot.dart       a picture of the content, and a long one (§2)
    import_old.dart       bringing data across from an earlier desktop app (§12)
    settings.dart         the desktop settings file
  lib/features/map/web/   the map in a WebView (§8)
  windows/ macos/ linux/  Flutter's runners, with a small native channel each (§2.7)
  android/                the phone's
  installers/             NSIS, WiX, deb, rpm, AppImage and dmg scripts (§10)
  integration_test/       tests that run on a real desktop build (§13)
```

- `lib/main.dart` checks `Platform.isWindows || isMacOS || isLinux` (and not a test). On the
  desktop it installs the host, runs the desktop start-up, then the **same** app widget, wrapped
  in the desktop chrome. Extra windows (widgets) start from `main(args)` with their own
  arguments and run only their small screen.
- Packages with no desktop build stay in `pubspec.yaml`. Flutter only registers a plugin on the
  platforms it declares; the Dart compiler only includes what's reachable. Code that would call
  one on the desktop asks `Native.has()` (false) or `Desktop.on` first.

---

## 2. The window, shell, and desktop UX

### 2.1 Packages

| Need | Package |
|---|---|
| Frameless window, size, place, maximise, full screen, always on top, close interception | `window_manager` |
| Tray icon, tooltip, menu, macOS menu-bar title | `tray_manager` |
| System notifications with clicks, on all three | `flutter_local_notifications` |
| More windows, each its own engine | `desktop_multi_window` |
| An image on the clipboard | `pasteboard` |
| Opening links in the browser | `url_launcher` |
| A WebView on all three | a `webview_flutter`-compatible desktop implementation (WebView2, WKWebView, WebKitGTK) |
| YAML, SHA-512, zips | `yaml`, `crypto`, `archive` |

Prefer packages that implement all three platforms; where one doesn't, the runner's native
channel fills in (§2.7).

### 2.2 The main window

- Hidden at creation; size and place read from the settings file; minimum size set (800×600); then
  maximised (unless it was last closed un-maximised) and shown once the first frame is drawn, so
  it never flashes white. Its background colour is the theme's.
- `setPreventClose(true)`: the close button hides it to the tray; Quit really quits. Before
  hiding, its normal bounds and maximised state are written.
- `TitleBarStyle.hidden` everywhere; on macOS the traffic lights stay (with
  `windowButtonVisibility: true`) and the title bar leaves them a 78 px inset; full screen drops
  the inset.

### 2.3 The title bar, command bar, and multi-pane shell

The app widget is wrapped (`MaterialApp.builder`) in the desktop chrome: a custom title bar on top,
a left `NavigationRail` (replacing the phone's bottom navigation bar), and a responsive workspace.

- **Drag**: `DragToMoveArea` (or `windowManager.startDragging()` on pan start); double-click
  maximises or restores.
- **Window buttons** (Windows, Linux): 46 px wide, full height, drawn to match the system's,
  close red on hover.
- **Subtle history & refresh**: compact icon buttons in the left corner of the title bar (next to
  the macOS traffic lights or app icon). A `NavigatorObserver` and the shell's page notifier track
  the active view; Back and Forward step through visited views. Refresh triggers the active view's
  reload callback (or `RefreshIndicator` if present) and shows a subtle spinner in the title bar.
- **The Command / Omni-Search Bar**: centered in the title bar (`Ctrl+K` / `Cmd+K` or `Ctrl+F` /
  `Cmd+F`). Acts as a native desktop command palette and search bar rather than a browser URL bar:
  - Typing searches stops, routes, or app commands live in a dropdown overlay.
  - Pasting a site URL (`https://...`) or app path (`#...`) and pressing Enter routes directly
    through `Links.open(url)`, keeping full URL parity without looking like a web browser.
  - Pressing `Ctrl+Shift+C` (`Cmd+Shift+C` on macOS) copies the current screen's shareable site URL
    to the clipboard with a toast.
- **Responsive Multi-Pane Workspace**: instead of centering a phone-shaped column on wide monitors,
  the shell adapts by window width:
  - **Compact (`< 720 px`)**: single pane, behaves like the phone shell.
  - **Medium (`720–1024 px`)**: left `NavigationRail` + single content pane, with maps expanding
    to fill the space.
  - **Expanded (`> 1024 px`)**: Master-Detail split view. The primary feature list (stops, search,
    favourites, routes) sits in a fixed-width left pane (360–400 px), while the active detail view
    (selected stop arrivals, route timetable, or interactive map) stays open alongside it on the
    right. Selecting an item in the left pane updates the right pane in place rather than pushing a
    full-screen route over the list.
- **Full screen**: screens that want it (a departures board) call `windowManager.setFullScreen`,
  and the title bar and navigation rail hide while it's on.

### 2.4 Desktop input, density, and adaptive surfaces

To feel like a native desktop app rather than a touch interface scaled up, `lib/desktop/adaptive.dart`
enforces desktop interaction patterns across shared widgets:

- **Compact density**: desktop `ThemeData` sets `VisualDensity.compact` and tightened list/card
  paddings so data-heavy views (timetables, arrival boards) show more rows without oversized touch
  margins.
- **Pointer & hover states**: interactive cards, rows, and chips show a subtle surface highlight on
  mouse hover and set `SystemMouseCursors.click`. Tooltips appear on hover after 400 ms for icon
  buttons.
- **Adaptive sheets (`AppSheet.show`)**: shared features never call `showModalBottomSheet` directly.
  They call `AppSheet.show()`, which opens a bottom sheet on Android, but on desktop opens either a
  **centered modal dialog** (for confirmations, pickers, settings) or a **right-hand slide-over
  inspector panel** (for filters, details, and secondary lists).
- **Right-click context menus**: list items (stops, services, favourites) wrap in a desktop context
  menu handler (`onSecondaryTapUp`), offering native right-click actions: *Open in Split Pane*,
  *Pin to Desktop Widget*, *Set as Tray Glance*, *Add/Remove Favourite*, and *Copy Link*.
- **Scroll physics**: Windows and Linux use a custom `ScrollBehavior` that disables Android's
  overscroll glow/stretch, enables mouse-wheel and trackpad smooth scrolling, and keeps a permanent
  or hover-expandable desktop scrollbar.

### 2.5 Native menu bar and keyboard shortcuts

- **macOS `PlatformMenuBar`**: renders a native system menu bar at the top of the screen with
  standard menus (*App*, *File*, *Edit*, *View*, *Window*, *Help*) wired to app actions:
  `Cmd+,` (Settings), `Cmd+K` / `Cmd+F` (Search / Command Bar), `Cmd+R` (Refresh), `Cmd+W` (Hide
  window), `Cmd+M` (Minimise), and `Cmd+Q` (Quit).
- **Cross-platform shortcuts** via `CallbackShortcuts` at the root:
  - `Ctrl+K` / `Ctrl+F` (`Cmd+K` / `Cmd+F`): focus Command / Search Bar
  - `F5` / `Ctrl+R` (`Cmd+R`): refresh current view
  - `Ctrl+,` (`Cmd+,`): open Settings
  - `Alt+Left` / `Alt+Right` (`Cmd+[` / `Cmd+]`): navigate Back / Forward
  - `Ctrl+W` (`Cmd+W`): close active dialog/panel, or hide window to tray
  - `Escape`: close active modal, command bar overlay, or exit full screen
  - `F11` (`Ctrl+Cmd+F`): toggle full screen

### 2.6 Theme on desktop

- **Product brand theme by default**: unlike Android 12+ (where Material You dynamic colours are on
  by default), the desktop app defaults to **the product's own look** (matching the web app's brand
  palette, custom typography, and light/dark/time-based mode).
- **Optional OS accent colour**: in Settings, desktop users can switch on *"Use system accent
  colour"*, which reads the OS accent colour (Windows DWM accent, macOS system accent, Linux
  portal/GTK accent) for primary highlights while keeping the product's own neutral surfaces and
  fonts—avoiding a full phone-like Material You pastel wash on desktop.

### 2.7 The runner's native channel

One `MethodChannel` per runner (`<app-id>/desktop`) for what no package does:

| Platform | Methods |
|---|---|
| Windows (C++) | single instance (a named mutex; the second copy sends its command line to the first with `WM_COPYDATA` and exits); the AppUserModelID (`SetCurrentProcessExplicitAppUserModelID`); Jump List tasks (`ICustomDestinationList` with `IShellLink`s to the exe plus a link argument); thumbnail toolbar buttons (`ITaskbarList3::ThumbBarAddButtons` and `ThumbBarUpdateButtons`, clicks from `WM_COMMAND` with `THBN_CLICKED`), with icons drawn in code |
| macOS (Swift) | URL events (`application(_:open:)`), the Dock badge (`NSApp.dockTile.badgeLabel`), the Dock menu (`applicationDockMenu`), login items (`SMAppService.mainApp`), keeping the app alive with no window (`applicationShouldTerminateAfterLastWindowClosed` false), reopen on Dock click |
| Linux (C) | single instance and forwarding (`G_APPLICATION_HANDLES_COMMAND_LINE` on a unique `GtkApplication`; the primary instance gets the second's arguments) |

Events come back to Dart on the same channel (`open` with a link, `thumb` with a button id,
`dock` with a menu index, `activate`).

---

## 3. The bridge host

The shared screens already ask the bridge for platform capabilities. The desktop installs a Dart
host behind it (`Native.host = DesktopHost()`), answering the same plugin calls, so screens need
no desktop branches:

| Call | Desktop answer |
|---|---|
| `info` → `features` | what the desktop does: notifications, alerts (polled), releases, update, check update, widgets, glance, … — never a phone-only feature |
| `openLink` | the browser (`url_launcher`), or the app itself for its own site |
| `share` | the clipboard and a "Link copied" note; named messaging apps open their web share links |
| `notify` | a system notification (§5) |
| `background` | hide to the tray |
| `releases` / `setReleases` | the update-notices switch in the settings file |
| `openSettings` | the system's own page where there is one (`ms-settings:privacy-location`, `x-apple.systempreferences:…`) |
| push registration | none: alerts are polled instead (§5) and nothing is sent to the push server |
| migration `read` | the earlier desktop app's stored data (§12) |
| `setFavourites` | the Jump List, thumbnail buttons and Dock menu (§7) |

Anything not listed fails like an absent plugin (`unavailable`), and the screen's plain path runs.

---

## 4. Location

`geolocator` covers Windows (Windows.Devices.Geolocation) and macOS (Core Location; the bundle
needs `NSLocationUsageDescription` and the location entitlement). On Linux it uses GeoClue over
D-Bus where present; where that fails (no GeoClue, no agent, denied), the app does its own
Wi-Fi lookup: `nmcli` scan, BeaconDB, the 3 km and `_nomap` rules and the GNOME switch from
`desktop-features-spec.md` §12. The shared location code asks one function, which picks.

---

## 5. Notifications and polling

- `flutter_local_notifications` initialised for all three: Windows with the app's name, its
  AppUserModelID and a GUID (it registers itself under `HKCU\Software\Classes\AppUserModelId`, so
  toasts work unpackaged); macOS asks once; Linux uses the freedesktop service with the app's icon.
- Each notification carries a payload (an in-app address or an action); the click handler shows
  the window and routes the payload. A click that starts the app arrives through the launch
  details.
- **Polling replaces push**: what the phone receives by push the desktop fetches on a timer while
  it runs (every minute for alerts), applying the same rules the server applies, with its own
  "seen" memory in storage. The first poll only records. Timers keep running while the window is
  hidden (a Flutter app isn't throttled when hidden; keep it that way by not pausing timers on
  `AppLifecycleState.hidden`).

---

## 6. More windows (desktop widgets)

- `desktop_multi_window` creates each widget as its own window and engine, passing
  `{ "kind": "widget", "id": … }` as arguments; `main(args)` starts the small widget app for it.
- Each widget window is frameless, skips the taskbar, can be pinned on top, and keeps its bounds
  (debounced writes) through the settings file. Its data comes from the same API client and
  storage (read-only) as the main app; a change it makes goes through the settings file.
- The windows talk to the main window over the package's method channel: "open this address",
  "close me", "saved".
- At start-up the main window reopens every kept widget; closing one with its × removes it;
  quitting keeps them.
- Runner hooks: the package's "window created" callback registers the plugins every new engine
  needs (window manager, the WebView if it's used, storage).

---

## 7. At a glance

The glance module owns a 30-second timer for the tray countdown and writes to every surface the
platform has: `trayManager.setToolTip` (127 characters on Windows), `trayManager.setTitle` and
the Dock badge on macOS. Favourites (set through the bridge) go to the Jump List and thumbnail
buttons (Windows, via the runner) and the Dock menu (macOS, via the runner). Jump List tasks
start the exe with an app link, which the single-instance forwarding delivers to the running app.

---

## 8. Maps in a WebView

The phone's native map SDK has no desktop build, but its JS build runs in a WebView:

- `lib/features/map/web/` holds an HTML page with the map engine's JS and CSS (pinned versions,
  bundled as assets, so it works offline), and a Dart controller with **the same methods the
  shared map code calls on the native controller** (add sources and layers, set GeoJSON, move and
  animate the camera, screen-to-map conversions, rendered-feature queries, the location dot). The
  shared map screen talks to an interface; on the phone the native controller implements it, on
  the desktop the WebView one.
- Commands go to JS with `runJavaScript`; events (camera idle, taps, style loaded) come back on a
  JavaScript channel as JSON.
- Layer properties serialise with the native SDK's own `toJson()` and are split into the engine's
  `paint` and `layout` objects on the JS side.
- **A local tile server**: a `HttpServer` on `127.0.0.1` (random port) serves the page and
  proxies the style, tiles, glyphs and sprites through a disk cache. "Save the map for offline"
  pre-fetches a region's tiles into the same cache, within the tile provider's terms, and the map
  works offline from it.
- Light and dark styles switch with the app's theme. The WebView's own context menu and
  navigation are blocked.
- On Windows, WebView2's remote debugging can be switched on by an environment variable for
  tests (§13).

---

## 9. Updating itself

Reads the same `latest*.yml` files an Electron updater would (`version`, `files[].url`, `sha512`,
`size`, `releaseDate`), from the newest release's download address:

| Install | Detect | Install an update |
|---|---|---|
| Windows `.exe` | `Uninstall <App>.exe` beside the exe | download `<app>-<v>-setup.exe` to temp, check SHA-512, start it with `/S --updated --force-run`, quit |
| Windows `.msi` | no uninstaller beside it | notify, link to the release |
| Linux AppImage | `APPIMAGE` set | download, check, write beside the AppImage, `chmod +x`, rename over it (atomic), start it, quit |
| Linux `.deb`/`.rpm` | installed under `/opt` or `/usr` | notify; the apt repository updates the `.deb` |
| macOS, writable | the bundle and its folder writable, not on `/Volumes/` or translocated | download the `.zip` for this processor, check, `ditto -x -k` into a temp folder; on quit a detached shell script waits for the process to end, swaps the bundle in (keeping the old if the move fails), clears quarantine, and reopens if asked |
| macOS, read-only | otherwise | notify |

Downloads stream to disk with progress for the update window. The check runs on start (in the
update window, up to 10 s), 30 s after, hourly, and after wake (`window_manager`'s or the
platform's resume event, or a monotonic-clock jump in the hourly timer).

---

## 10. Installers

All built from `flutter build <platform> --release` output, by scripts in `installers/`:

- **Windows `.exe` (NSIS)**: per user, asks for the folder (default
  `%LOCALAPPDATA%\Programs\<App>`, or the folder an earlier install recorded), x64 and Arm64
  payloads in one installer picking by `PROCESSOR_ARCHITECTURE`/`IsWow64Process2`. Closes a
  running copy first, clears the folder (so an earlier framework's files go), installs, writes the
  uninstaller with the old name and the same uninstall registry key and install-location key an
  earlier installer used, Start menu and desktop shortcuts with the AppUserModelID set, and
  registers the URL scheme. Honours `/S` (silent), `--updated` and `--force-run` (start the app
  after a silent install), as an Electron updater passes them.
- **Windows `.msi` (WiX)**: x64, per user, a `MajorUpgrade` with the **same UpgradeCode** an
  earlier MSI used, the same shortcuts.
- **macOS**: the `.app` (ad-hoc signed with `codesign -s -`), a `.zip` of it with `ditto -c -k
  --keepParent` (for updates), and a `.dmg` with an Applications link (`hdiutil`). Built once per
  processor (`--release` with `ARCHS`), named `-mac-arm64` and `-mac-x64`.
- **Linux**: the bundle into `/opt/<App>/`, a symlink on the `PATH`, the `.desktop` file (with
  `MimeType=x-scheme-handler/<scheme>;` and `StartupWMClass`), icons in `hicolor`; `.deb` with
  `dpkg-deb` (same package name as before, dependencies on GTK 3 and the WebView's WebKitGTK),
  `.rpm` with `rpmbuild`, AppImage with `appimagetool` (an `AppRun`, the `.desktop` and icon at the
  root). One set per processor, built on that processor.
- **Update files**: a script writes `latest.yml`, `latest-mac.yml`, `latest-linux.yml` and
  `latest-linux-arm64.yml` (version, files with base64 SHA-512 and size, path, release date) in
  the Electron updater's format, so older apps update too.

---

## 11. CI

A workflow on `release: published` (and by hand with a tag) runs a matrix, each job on the
right machine: `windows-latest` (x64) and `windows-11-arm` (Arm64) building their halves, then a
Windows job combining both into the NSIS `.exe` and building the `.msi`; `macos-latest` building
both Mac processors; `ubuntu-latest` and `ubuntu-24.04-arm` each building `.deb`, `.rpm` and
AppImage. Jobs install Flutter (pinned version), the system packages (Linux: `ninja-build`,
`libgtk-3-dev`, `libwebkit2gtk-4.1-dev`, `rpm`, …), run `flutter test` once, build, package,
write the `.yml` files, and upload everything to the release with `gh release upload --clobber`,
creating a draft if the tag has no release. The apt repository job runs after.

---

## 12. Taking over from an earlier desktop app

When the desktop app replaces one built on Electron (or any Chromium shell):

- **Same names and places** (§0, §10) so the old updater installs the new app and its shortcuts,
  Jump List and scheme handler keep pointing at it.
- **The settings file is read in place.** Same folder, same keys.
- **The site's stored data is read from Chromium's LevelDB**: `<settings folder>/Local
  Storage/leveldb/`. A small Dart reader (no native dependency): the `CURRENT` file names the
  manifest; read every `.log` (write-ahead log: 32 KiB blocks of records, each record a batch of
  puts and deletes with a sequence number) and every `.ldb` table (footer, index block, data
  blocks with prefix-compressed keys, Snappy-compressed blocks; Snappy decoding is a few dozen
  lines). Keep the highest sequence number per key, drop deletions. Keys are
  `_<origin>\x00\x01<key>`; values start with `0x01` (Latin-1 bytes) or `0x00` (UTF-16LE).
  The site's keys become the migration's items (the same path the phone's WebView migration
  uses), copied once, never over values the app set since.
- Chromium's caches in the old folder can be deleted after a successful import; its storage is
  left alone.
- Test the reader against a real profile written by the old app.

---

## 13. Testing

- **Unit and widget tests** (`flutter test`) for every desktop module that has logic: the
  command bar & link parser, responsive split-pane state, the update file parser and install-type
  detection, the LevelDB reader (with a fixture written by a real Chromium), the alerts polling
  rules, the glance formatting, the widget layout, the welcome window's choices.
- **Integration tests** (`flutter test integration_test -d windows|macos|linux`) on a real build:
  the main window opens, the title bar's buttons and command bar work, the multi-pane layout splits
  on wide windows, adaptive dialogs/drawers open instead of bottom sheets, the welcome window
  applies its choices, a link opens the right screen, a widget opens and saves.
- **The map's WebView** with Playwright: the page alone in Chromium (layers added, camera moves,
  events posted), and inside the Windows app by starting it with
  `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--remote-debugging-port=<port>` and attaching with
  `chromium.connectOverCDP`.
- **The guide's screenshots** of the desktop screens (welcome window, update window, title bar &
  split-pane shell, widget) rendered by the test renderer at 2× or 3× from fixed data, light and
  dark, as the phone's are.

---

## 14. Checklist

- [ ] Desktop start-up in `main.dart`; the same app widget; extra windows from `main(args)`
- [ ] Window: hidden until drawn, size and maximised state kept, close to tray, macOS insets
- [ ] Title bar & shell: drag, buttons, command/search bar, `NavigationRail`, responsive Master-Detail split panes, full screen
- [ ] Desktop UX: `VisualDensity.compact`, hover states, `AppSheet` (dialogs/side-drawers instead of bottom sheets), right-click context menus, desktop scrollbars
- [ ] Native macOS `PlatformMenuBar` and standard desktop shortcuts (`Ctrl/Cmd+K`, `Ctrl/Cmd+,`, `Ctrl/Cmd+W`)
- [ ] Theme: defaults to the product's brand look on desktop; optional OS accent colour
- [ ] Runner channels: single instance and forwarding, AppUserModelID, Jump List, thumbnail
      buttons, Dock badge and menu, login items, URL events
- [ ] Bridge host answering every call the screens make
- [ ] Location on all three, the Linux fallback
- [ ] Notifications with clicks; polling in place of push
- [ ] Widget windows in their own engines
- [ ] Glance surfaces per platform
- [ ] Map in a WebView with a local caching tile server and offline save
- [ ] Updater per install type, SHA-512 checked, update window
- [ ] Installers per platform, update files in the old format, CI on release
- [ ] Old app's updates install the new one; settings and site data carried across
- [ ] Unit, integration and Playwright tests; deterministic screenshots