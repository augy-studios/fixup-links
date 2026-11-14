# Desktop features: everything a desktop app adds over its website and phone app

A checklist of every capability that belongs to a desktop app (Windows, macOS and Linux) and to
neither the website (and its PWA) nor the phone app. It's written for rebuilding a desktop app
on a new framework without losing anything: each feature says what the person sees, how it
behaves at its edges, what it keeps on disk, and how to check it works. Nothing here is tied to
one framework; `flutter-desktop-app-spec.md` says how to build these in Flutter.

Words used throughout:

- **The app**: the desktop app.
- **The site**: the same product's website. The desktop app has every feature the site has; this
  document only lists what it adds.
- **The main window**: the app's one big window. Other windows (the welcome window, the update
  window, desktop widgets) are named as they come.
- **The live item**: whatever the product tracks in real time that a person might want to keep an
  eye on outside the window, such as the next arrivals at a place they picked. Examples below say
  "item" for it.
- **Favourites**: the items a person has starred in the app.
- **The settings file**: one small JSON file of the app's own, in its per-user data folder (§20).

Every feature lists its **keys** in the settings file, so a rebuild can read what the old app
kept. Keys are given in `code` and must keep their names and meanings across a rebuild.

---

## 0. The rule that holds it together

1. **The site keeps every base feature.** Nothing here replaces something the site does in a
   browser; each is an extra on top. A browser-only path (Web Push, the browser's own location,
   copy to share) stays working.
2. **The app keeps every site feature.** Rebuilding the app natively must not drop a screen,
   setting, word or behaviour the site has. Desktop extras sit beside them.
3. **One version number.** The desktop app shares its version with the phone app, so one release
   carries every platform's installers.
4. **Nothing secret on the computer.** No API key, token or password lives in the app or its
   settings file.

---

## 1. The welcome window ("Make it yours")

The first window a new install opens with, and the first window after updating to the first
version that has it. Afterwards, the tray's menu opens it again (§4).

### What it shows

A window about 940 × 660 (minimum 620 × 560), in two columns:

- **Left, a welcome panel** (about a third of the width, hidden below 760 px wide): the app's
  icon (72 px, rounded), "Welcome to {App}", a one-line tagline, and three of the app's headline
  features, each with an icon. Its background is the brand colour as a gentle top-to-bottom
  gradient, with two soft translucent circles in its corners. Its writing is dark on a light
  brand colour.
- **Right, the choices**: a heading ("Make {App} yours"), a line under it ("Choose how the app
  should look and feel."), then one row each, every row a rounded card with an icon tile, a
  label and its control:

  | Row | Control | Values |
  |---|---|---|
  | Language | drop-down | Automatic, then each of the site's languages by its own name |
  | Start when I sign in | switch | on / off |
  | Follow system theme | switch | on: the computer's light or dark; off: the Theme row decides |
  | Theme | drop-down, greyed out while Follow system theme is on | Light, Dark, Time-based (dark from 18:00 to 09:00) |
  | Brand colour | a row of round swatches, the picked one ringed, plus an optional "System accent" swatch | the site's brand colours, each with its name as a tooltip and accessible label, or the OS accent colour |

- **A footer**: "You can change these any time, from Make it yours in the tray's menu.", and a
  **Get started** button in the brand colour with an arrow.

### How it behaves

- **It previews as you pick.** Choosing a theme repaints the window light or dark; choosing a
  colour repaints the panel and the button; choosing a language rewrites every word of the window
  at once, including the window's title. Automatic follows the computer's language.
- **Its words are its own,** in each of the site's languages, as the main window may not have
  loaded yet. They must cover every label above, the Automatic option, the theme names, the
  footer, the button and the notes below.
- **It reads what's set.** It opens at once with defaults (Automatic, start at sign-in on,
  Light, the first brand colour), then fills in the person's current language, theme mode and
  colour as soon as the app can say, leaving alone anything the person has already touched in
  the meantime. It waits up to about five seconds for that; after that the defaults stand.
- **Rules the site has for colours apply.** A colour the site keeps locked (a seasonal or earned
  one) shows greyed with a lock and can't be picked. A colour that's only offered until a date
  isn't offered after it. If the person's own custom colours (a site feature that overrides
  the brand colour) are on, the swatches hide and a note says the brand colours wait until those
  are turned off. Unlike the Android app (where Material You is on by default), the desktop app
  defaults to the product's own brand colour and typography unless the person chooses the system
  accent option.
- **Get started** applies everything through the same functions the app's own settings use (so
  there's one set of settings, not two): the language, the theme mode, and the brand colour
  unless custom colours are on. It sets start at sign-in to what the switch says (§6), marks
  that choice as made, closes the window, and opens the main window.
- **Closing the window any other way changes nothing,** but still counts as having seen it: it
  won't open by itself again.
- **Applied late, if need be.** If the app can't apply the choices yet (the first launch with
  no connection, say), they're kept and applied the next time it can, then forgotten.
- Respects reduced motion (no transitions). Keyboard: every control reachable by Tab, swatches
  as a radio group with a visible focus ring.

### Keys

`setupDone` (true once seen), `pendingLook` (`{ lang, mode, color }` waiting to be applied, or
null), `loginChosen` (§6), `useSystemAccent` (optional boolean, false by default).

### Check

A fresh profile opens the welcome window before the main window; switching the language rewrites
it; Dark repaints it; closing it opens the main window with nothing changed; reopening the app
doesn't show it again; the tray's Make it yours... shows it with the current choices filled in.

---

## 2. The update window at launch

A small frameless window (300 × 360, centred, not resizable, draggable by anywhere) that opens
before the main window on every launch of an installed copy:

- The app's icon, gently bobbing (still under reduced motion), and a line of status under it.
- **Checking for updates…** with an indeterminate bar, for up to 10 seconds.
- If there's a newer version **that this install can install itself** (§3): **Downloading
  update**, "Version x.y.z" then "31 of 85 MB", a determinate bar, and **Later** under it.
  Then **Installing update…** and the app restarts as the new version without opening its old
  main window.
- **Later** opens the app at once and leaves the download to finish in the background, ready
  for Restart to update (§3).
- Nothing new, offline, a check that took too long, a failed download, or an install that can
  only be told about it (§3): **Starting…** for half a second, then the main window.
- Light or dark as the computer is, with its own colours, not the brand colour.
- A developer switch runs it through every step with made-up numbers, for seeing it without a
  release.

Restart to update (§3) shows the same window saying **Installing update…** while it goes.

---

## 3. Updating itself

The app finds, downloads and installs its own new versions from the project's public release
page; there's no store.

### Finding them

- The release carries one small update file per platform (`latest.yml` for Windows,
  `latest-mac.yml`, `latest-linux.yml`, `latest-linux-arm64.yml`), each giving the version, the
  installer's file name, its size and its SHA-512 (base64). The app reads the one for its
  platform and processor from the newest release's download address, which always points at the
  newest release.
- When: at launch (§2), then 30 seconds after the main window, then every hour, and 20 seconds
  after the computer wakes from sleep.
- Each check is a few kilobytes and doesn't use a rate-limited API.

### What each install can do

| Installed with | Can install an update itself? | How |
|---|---|---|
| Windows `.exe` installer (per user) | yes | download the new `.exe`, verify SHA-512, run it silently, and it reopens the app |
| Linux AppImage | yes | download the new AppImage, verify, replace the running file, reopen |
| macOS app in a folder the person can write to | yes | download the new `.zip`, verify, unzip beside it, swap the app bundle in once the app has quit, clear the quarantine flag, reopen |
| Windows `.msi`, Linux `.deb` or `.rpm`, a Mac app on a read-only volume or translocated, a copy run from source | no | only say there's a new version, with a link to download it |

The `.exe` install is told apart by the uninstaller it leaves beside the app.

### What it says

- **"{App} x.y.z is out"** when a new version is found that this install can't install itself
  (click: the release page), or, when the person asked (below), that it's downloading.
- **"{App} x.y.z is ready"** once downloaded: "Click to restart and update. Otherwise it updates
  the next time you quit." Click: Restart to update.
- **"Couldn't download {App} x.y.z"**, once per version, if a found version doesn't download or
  won't unpack: "It tries again within the hour, or click to download it from GitHub."
- Each said **once per version**, and only while the person's **New versions of the app** switch
  is on (§13). A failed check (offline) says nothing unless asked for.
- **Check for updates...** in the tray's menu checks now and always says what it found: up to
  date ("x.y.z is the newest version"), downloading, ready, or "Couldn't check for updates".
  While it runs, the item reads "Checking for updates..." and is greyed out.
- The tray's menu gains **Restart to update to x.y.z** once one's ready, or **Download version
  x.y.z** for an install that can't do it itself. The title bar gains a green update button
  (§5).
- An update that's downloaded is installed when the person quits, if they never restart for it.
- Run from source, Check for updates... says there's nothing to update.

### Keys

`updateNotices` (false when New versions of the app is off; missing means on).

---

## 4. The tray (the menu bar on macOS)

- An icon in the system tray, drawn for each pixel density (16, 32, 48 px), the product's
  silhouette; a template image on macOS so it follows the menu bar's colour.
- Its tooltip is the app's name, or the live item's countdown (§9).
- **Click** (Windows and Linux): shows and focuses the main window, or hides it if it's already
  in front. macOS opens the menu on click.
- **Menu**, top to bottom:
  1. Restart to update to x.y.z / Download version x.y.z (only while there is one), separator
  2. The tray countdown's two items (§9), when one's set, separator
  3. Open {App}
  4. Two of the product's most-used pages, each opening the main window on that page
  5. Add a {widget} (§8)
  6. Make it yours... (§1)
  7. separator, Check for updates... (§3)
  8. Start when I sign in, a check box (§6)
  9. separator, Quit
- The menu is rebuilt each time it opens (so the check box is true) and whenever an update or
  countdown changes it.

---

## 5. The main window, title bar, and desktop layout

### The window

- Default un-maximised size 1120 × 760, minimum 800 × 600 (compact fallback down to 360 × 520 if
  resized narrow). **Opens maximised** unless it was last closed un-maximised; its un-maximised
  size and place are kept and used next time, if they're still on a screen.
- **Closing it keeps the app running** in the tray (§4). The first time, a notification says so:
  "{App} is still running. It keeps checking for alerts from the tray. Quit it from the tray
  icon." (macOS: "from the menu bar. Quit it from the menu bar icon, or with ⌘Q.") Quit is in the
  tray's menu (and ⌘Q on macOS).
- **One copy at a time.** Opening the app again (a shortcut, a sign-in, a link) brings the
  running one forward instead, on the link's page if it came with one.
- The app's identity for the system (Windows' AppUserModelID, the macOS bundle id, the Linux
  `.desktop` name) stays the same forever: notifications, the taskbar group, pins and Jump Lists
  hang on it.

### The title bar and command bar

The system's title bar is replaced by the app's own, 40 px tall, in the app's current brand
colour (writing light or dark by contrast with it), and draggable where there's nothing to
click. Double-clicking it maximises or restores. Left to right:

| Part | What it does |
|---|---|
| (macOS) the traffic lights | the system's own, over the bar's left, which leaves them room |
| Back, Forward | compact buttons stepping through the app's own view history, greyed out when there's nowhere to go |
| Reload | refreshes the active view, spinning while it loads |
| The Command / Search Bar | centred in the bar. Shows the current view's title or path at rest; clicking or pressing `Ctrl+K` / `Ctrl+F` (`⌘K` / `⌘F`) opens a live search for stops, routes, or app commands. Pasting a site address (`https://…`), path (`/#…`, `#…`), or app link (§10) and pressing Enter opens it in the app; another site's address opens in the browser; Esc closes and restores it |
| Copy link | copies the current view's shareable site address; "Link copied" shows in the bar for 1.5 s |
| Screenshot | a picture of the app's content (not the bar), copied to the clipboard and saved in the Downloads folder as `{App} YYYY-MM-DD HH.MM.SS.png`; a notification "Screenshot saved", click to show it in its folder |
| Long screenshot | the whole of the active scrollable pane, top to bottom, not just the visible part, up to 16384 px tall; saved as `… (long).png`, "Long screenshot saved". Sticky headers are drawn once, at the top. Only one screenshot at a time; the buttons dim while it's taken |
| Update | green, only while an update is downloaded: Restart to update (§3) |
| (Windows, Linux) minimise, maximise/restore, close | full bar height, 46 px wide each; close turns red on hover and keeps the app in the tray |

Messages from the bar ("Link copied", "Screenshot copied and saved", "Couldn't take a
screenshot", "Opened in your browser", "Not found") show for 1.5 s over the command bar.

### Multi-pane layout, density, and desktop interactions

Unlike the phone app (which stacks single full-screen pages and uses bottom bars and bottom
sheets), the main window uses desktop space and mouse/keyboard conventions:

- **Left navigation rail**: primary sections sit in a vertical rail on the left edge instead of a
  bottom navigation bar.
- **Responsive split panes**:
  - Below 720 px wide: single column, like the phone app.
  - 720–1024 px wide: navigation rail plus a single main content pane.
  - Above 1024 px wide: **Master-Detail split view**. Lists (stops, favourites, search results,
    routes) stay open in a 360–400 px left pane while the selected item's live arrivals, route
    timetable, or interactive map renders simultaneously on the right.
- **Compact density & hover states**: rows, tables, and buttons use compact desktop spacing so
  more arrivals and stops fit on screen, with hover highlights and pointer cursors on clickable
  items.
- **Dialogs and side drawers instead of bottom sheets**: secondary panels (filters, pickers,
  settings, details) open as centred modal dialogs or right-hand slide-over drawers rather than
  phone-style bottom sheets.
- **Right-click context menus**: right-clicking a stop, service, or favourite opens a menu with
  *Open in Split Pane*, *Pin to Desktop Widget*, *Set as Tray Countdown*, *Star / Unstar*, and
  *Copy Link*.

### Native macOS menu bar and keyboard shortcuts

On macOS, the system menu bar at the top of the screen includes standard *App*, *File*, *Edit*,
*View*, *Window*, and *Help* menus wired to the actions below. Across all three platforms:

- **Search / Command Bar**: `Ctrl+K` or `Ctrl+F` (`⌘K` or `⌘F` on macOS), or `Ctrl+L` / `F6` (`⌘L`).
- **Copy current link**: `Ctrl+Shift+C` (`⌘⇧C`).
- **Back / Forward**: `Alt+Left` / `Alt+Right` (`⌘[` / `⌘]`).
- **Reload**: `F5` or `Ctrl+R` (`⌘R`).
- **Settings**: `Ctrl+,` (`⌘,`).
- **Close panel or hide window**: `Ctrl+W` (`⌘W`); `Esc` closes an open dialog, drawer, or
  command bar overlay, or exits full screen.
- **Full screen**: `F11` (`⌃⌘F`).

### Full screen

When a page asks to go full screen (a departures board, a video) or the person presses `F11`
(`⌃⌘F`), the window goes full screen and the title bar and navigation rail hide; leaving full
screen brings them back.

### Keys

`bounds` (`{ x, y, width, height }`), `maximized`, `trayHintShown`.

---

## 6. Starting when the person signs in

- **On by default** from the first run of an installed copy (not from source), and the welcome
  window's switch and the tray's check box turn it off. Once the person has chosen, that choice
  sticks across updates.
- It starts the app as any other start (maximised main window, after the update window).
- Windows: the per-user login items. macOS: the login items. Linux: a `.desktop` file in
  `~/.config/autostart/` with `X-GNOME-Autostart-enabled=true`; for an AppImage, its `Exec` is
  the AppImage file itself, not the temporary mount.

### Keys

`loginChosen`.

---

## 7. Notifications on the desktop

The desktop has no Web Push and no phone push service, so the app looks for itself and shows
system notifications, with the app's icon and name:

- **Alerts the person subscribed to** (the product's service alerts and its newsfeed of
  announcements, by the same choices as the site: all, only disruptions, or off for each kind):
  checked **every minute** while the app runs, open or in the tray, by the same rules as the
  server uses for push: a change in a line's state, new incidents not seen in the last while
  (the first check only records what's there), and newsfeed items not seen before filtered by
  the same keyword rules. One notification sums up a batch ("And 2 more…"). Click: the alerts
  page. The disruptions bar on the main window updates from the same check.
- **The trip alert** (the product's "time to get off" alert, or its equivalent), and anything
  else the site would show as a browser notification, comes as a desktop notification.
- **Update notifications** (§3), **screenshot saved** (§5), **still running** (§5).
- Clicking any notification brings the main window forward, on the page it names.
- Notifications are allowed without asking on Windows and Linux; macOS asks once.

---

## 8. Desktop widgets

Small frameless windows on the desktop, each showing one item's live data (for example the next
arrivals at a chosen place), because a third-party desktop app can't add to the system's widget
board.

- **Added from the tray**: Add a {widget} (or by right-clicking an item in the main window and
  choosing *Pin to Desktop Widget*). A new widget opens in its setup state: pick one of the
  favourites, or type an item's code; optionally narrow it to some sub-items (typed as a
  comma-separated list); Save.
- **Shows** as many rows as fit, scrolling for the rest; each row the sub-item and its next two
  times, counting down between refreshes (every 15 s) and refreshed from the server every 30 s.
  Honours the site's "clock times" setting (times as 14:05 rather than "5 min").
- **Its own buttons**: refresh now, change what it shows (back to setup), pin on top of other
  windows (a toggle), and remove (×).
- **Moved** by dragging its top; **resized** from any edge, down to 200 × 110. Default 320 × 300.
- **Clicking a row** opens that item and sub-item in the main window.
- **Kept**: each widget's item, sub-item filter, name, pin and place are saved, and every widget
  reopens where it was when the app starts. Removing one with × forgets it; quitting the app
  keeps them all.
- Widgets don't appear in the taskbar or the Alt+Tab list.
- Dark by default with its own compact look; respects the app's theme mode.

### Keys

`widgets`: `[{ id, code, name, buses|items: [..], onTop, bounds }]` (keep the old field names
when rebuilding, so existing widgets come back).

---

## 9. At a glance: the tray countdown, the Jump List and the Dock

### The tray countdown

- On an item's page (only inside the app) or its right-click context menu, a **Tray countdown**
  button. Pressed, the item (or, if the page is narrowed to one sub-item, just that) is followed
  outside the window, and the button reads "In the tray" for 2.5 s.
- Every 30 s the app fetches its next times and shows them:
  - **Windows and Linux**: the tray icon's tooltip, the item's name then one line per sub-item
    ("12: 3 min, 14 min", "Arr" for arriving now), soonest first, cut to 127 characters with an
    ellipsis. "No {sub-items} due right now" when none; "{name}: couldn't get the times just
    now" on failure.
  - **macOS**: also as text beside the menu bar icon (" 12 · 3 min") and as the Dock icon's badge
    (the soonest minutes, or "Arr").
- The tray menu gains "Tray countdown: {item}" (opens it) and **Stop the tray countdown**.
- Kept across restarts.

### Favourites outside the window

The favourites (up to 10, sent by the app whenever they change):

- **Windows Jump List** (right-click the taskbar icon): one task per favourite, "Name (code)",
  each opening it in the app through an app link (§10).
- **Windows taskbar thumbnail buttons** (hover the taskbar icon): Previous favourite, Refresh,
  Next favourite, white 16 px glyphs; previous and next greyed out with fewer than two
  favourites. Refresh refreshes what's on screen without bringing the window forward; previous
  and next open that favourite in the main window, cycling round the list.
- **macOS Dock menu**: one item per favourite; "Star an item to see it here" when there are none.

### Keys

`trayStop` (`{ code, name, service }` or null), `favourites` (`[{ code, name }]`).

---

## 10. App links (`{scheme}://{app}/…`)

- Links like `{scheme}://{app}/{path}` open the app on the page they name, exactly as the phone
  app maps them: `{scheme}://{app}/` the home page; the site's short links by their path (e.g.
  `go/{id}`); anything else as the site's in-app address (`{scheme}://{app}/{item}`,
  `/route/{n}`, `/map/{item}`…). Only plain path characters are accepted.
- **Registered at every start**, for the person's account (Windows: `HKCU\Software\Classes`),
  so links keep working after an update or a move. macOS: the bundle's URL types. Linux: the
  `.desktop` file's `MimeType=x-scheme-handler/{scheme}`.
- **Shared with sibling apps.** A desktop OS gives a scheme to one app only, unlike a phone, which
  shares it out by host. So every sibling app does the same handoff: at start, note which app
  holds the scheme now (if it isn't this app), then take it; a link for another host is passed
  to the app noted, with this one left where it was. Whichever app started last holds the scheme
  and passes the others their links. The note is kept, and an app started only to pass a link
  on quits at once without opening a window. Links are passed as one argument, never through a
  shell. On Linux the handler's `.desktop` file is read for its `Exec` line, with `%u` and
  friends filled in.
- An AppImage only gets links once it's been added to the desktop's menu.

### Keys

`linkHandoff` (`{ command }` on Windows, `{ app }` on macOS, `{ desktop }` on Linux).

---

## 11. Links out

Every link to anything but the product's own site opens in the person's own browser (or mail
app for `mailto:`). The site's own addresses stay in the app.

---

## 12. Location on every desktop

Pages that use the computer's location (items near me, navigation, the live map, a trip) work:

- **Windows**: the system's location, when Settings > Privacy & security > Location is on.
- **macOS**: the system's location, once allowed (the bundle carries usage descriptions).
- **Linux**: the system location service if present; otherwise the app finds it itself: it scans
  Wi-Fi with NetworkManager (`nmcli -t -f SSID,BSSID,SIGNAL,FREQ dev wifi list --rescan auto`),
  drops networks whose name ends `_nomap`, takes up to 40 strongest, converts signal 0–100 to
  dBm (`signal/2 - 100`), and asks BeaconDB (`POST https://api.beacondb.net/v1/geolocate`,
  `{ considerIp: true, wifiAccessPoints: [{ macAddress, signalStrength, frequency }] }`) with a
  user agent naming the app. It refuses anything less accurate than 3 km (an internet-address
  guess), keeps an answer for 4 s so a trip's steady asking doesn't rescan, and respects GNOME's
  Location Services switch (`gsettings get org.gnome.system.location enabled`): off, it says so
  and doesn't look. Only hardware addresses and strengths leave the computer.
- Errors read as the site's do: not allowed (with how to turn it on), or couldn't tell (with a
  suggestion to type a place).

---

## 13. Hooks in the shared pages that only the desktop shows

Features of the site or the shared screens that switch on only in the desktop app:

| Where | What the desktop adds |
|---|---|
| An item's page & right-click menu | **Tray countdown** and **Pin to Desktop Widget** actions (§8, §9) |
| Shared sheets & modals | Open as centred dialogs or right-hand slide-over drawers instead of bottom sheets (§5) |
| Alerts settings | Notifications are always available (no browser permission); **New versions of the app** switch, kept by the app (§3) |
| Appearance settings | Defaults to the product's brand look; optional **Use system accent colour** toggle (§1) |
| Alerts | the every-minute check and newsfeed notifications (§7) |
| A trip | its alerts as desktop notifications (§7) |
| Favourites | sent to the app whenever they change (§9) |
| The widget page | the pin-on-top button, and its item kept by the app per widget (§8) |
| Bug reports | name the platform as "desktop" and include the app's version |
| Location | uses the app's location on Linux (§12) |
| The app's version | shown wherever the site shows the app's version |

---

## 14. Permissions

The app's content may use the computer's location and notifications, write to the clipboard and
go full screen. Anything else it asks for (camera, microphone, MIDI…) is refused.

---

## 15. Offline first launch

If the very first launch has no connection and nothing is kept yet, the app says so plainly ("No
connection: {App} needs the internet the first time it opens. Check your connection, then try
again.") with a **Try again** button, rather than a blank window. Once it has run once, it opens
offline with what it kept.

---

## 16. Installers

| Platform | Files | Notes |
|---|---|---|
| Windows | `{app}-{v}-setup.exe` (x64 and Arm64 in one, installs the right one), `{app}-{v}.msi` (x64, for Group Policy / `msiexec`) | per-user, asks where to install, Start menu and desktop shortcuts, an uninstaller; the `.exe` opens the app when it finishes |
| macOS | `{app}-{v}-mac-arm64.dmg`, `-mac-x64.dmg`, and a `.zip` of each for updating | drag to Applications; category Travel (or the product's) |
| Linux | `.deb` (amd64, arm64), `.rpm` (x86_64, aarch64), `.AppImage` (x86_64, arm64) | menu entry with the scheme handler; executable on the PATH |
| All | the `latest*.yml` update files (§3) | uploaded with the installers on every release |

- Each installer's name keeps its old pattern, so links and update files keep working.
- **An apt repository** (signed, on static hosting) carries the newest `.deb`s, so `apt upgrade`
  brings new versions on Debian-family systems.
- Not signed with a paid certificate: Windows SmartScreen warns once ("More info > Run anyway");
  macOS needs right-click > Open (or System Settings > Privacy & Security > Open Anyway), and
  `xattr -cr` if it says the app is damaged. The guide says so.

---

## 17. Building on CI

- Publishing a release builds every platform from the release's tag, on each platform's own
  machine, and attaches the installers and update files to it, unless they're there already.
- Run by hand with a tag: builds and attaches them, creating a draft release if there's none.
  With no tag: builds and keeps the files on the run for a while, to try a build.
- Arm builds run on Arm machines where the framework can't cross-compile.

---

## 18. Taking over from an older desktop app

When the desktop app is rebuilt on a new framework, the new version must arrive as an ordinary
update and keep everything:

- **Updates in place.** The old app's updater must be able to install the new version: same
  update files, same installer file names, the Windows installer at the same per-user location
  with the same uninstall entry, handling the old updater's silent-install arguments, and
  removing the old framework's files. The same package names for `.deb` and `.rpm`, the same
  `.app` name on macOS, the same executable name on Windows (so shortcuts, Jump List tasks and the
  registered scheme handler still point at it).
- **Brings the data across**, once, on first open: everything the old app kept in its embedded
  browser's storage for the site (favourites, places, history, settings, every key) and the
  settings file (§20). Nothing is asked of the person.
- **Doesn't show the welcome window again** to someone who saw it in the old app.

---

## 19. The guide

The product's guide has a desktop page covering: download and install per platform (with the
unsigned-app steps), the apt repository, Make it yours (with screenshots, light and dark), the
tray, the tray countdown, favourites on the taskbar and Dock, notifications, widgets, starting at
sign-in, app links and sibling apps, updates (with the update window's screenshots, light and
dark), the title bar, command bar, split-pane layout and screenshots, and location per platform.

---

## 20. The settings file

One JSON object in the app's per-user data folder (`%APPDATA%\{App}\settings.json`,
`~/Library/Application Support/{App}/settings.json`, `~/.config/{App}/settings.json`). Read and
merged on every write, so two parts of the app writing different keys never undo each other. A
failed read is an empty object; a failed write is ignored. All keys, from the sections above:

`bounds`, `maximized`, `trayHintShown` (§5), `loginChosen` (§6), `updateNotices` (§3),
`setupDone`, `pendingLook`, `useSystemAccent` (§1), `widgets` (§8), `trayStop`, `favourites` (§9),
`linkHandoff` (§10).

---

## 21. Checklist

- [ ] Welcome window: first run, after the update that introduces it, from the tray; previews;
      four languages; colour rules (brand default, optional system accent); Get started applies;
      close changes nothing (§1)
- [ ] Update window at launch: checking, downloading with Later, installing, starting, light and
      dark (§2)
- [ ] Updates: every hour, after wake, tray check with all four answers, per-install behaviour,
      once-per-version notifications, the switch, install on quit, SHA-512 checked (§3)
- [ ] Tray icon, click to show and hide, full menu (§4)
- [ ] Window size (desktop-proportioned default) and maximised state remembered; close to tray with
      the first-time hint; one copy at a time (§5)
- [ ] Title bar & shell: back, forward, reload, Command / Search Bar (with URL paste support),
      copy link, screenshot, long screenshot, update button, window controls, brand colour, hidden
      in full screen (§5)
- [ ] Desktop UX: left navigation rail, responsive Master-Detail split panes (`> 1024 px`),
      compact density, dialogs/drawers instead of bottom sheets, right-click context menus, macOS
      menu bar, and desktop keyboard shortcuts (§5)
- [ ] Start at sign-in on by default, sticky choice, per platform (§6)
- [ ] Alert and newsfeed notifications every minute; trip alerts; clicks open the page (§7)
- [ ] Widgets: add, setup, rows, refresh, change, pin, remove, move, resize, click a row, restored
      at start (§8)
- [ ] Tray countdown on every platform's surfaces; Jump List; thumbnail buttons; Dock menu and
      badge (§9)
- [ ] App links: open, registered per start, handoff to sibling apps both ways (§10)
- [ ] Other sites open in the browser (§11)
- [ ] Location on each platform, the Linux Wi-Fi fallback and its privacy rules (§12)
- [ ] Each shared-page hook (§13); permissions (§14); offline first launch (§15)
- [ ] Every installer and update file, the apt repository, CI on release (§16, §17)
- [ ] Old app updates to the new one in place, data and settings carried across (§18)
- [ ] The guide's desktop page and its screenshots (§19)