# uwuFix - Link Fixer

Clean URLs, remove trackers, and fix embeds - all in your browser.

## Features

- **Tracker Removal** - Strips UTM parameters, click IDs, Klaviyo tracking (`_kx`, `tw_source`), and platform-specific tracking from any URL
- **Embed Fixing** - Converts links to embed-friendly domains for better previews on Discord, Telegram, and more:
  - X/Twitter → `fixupx.com` (usernames replaced with `i`)
  - Instagram → `kkclip.com`
  - TikTok → `kktiktok.com` / `vt.kktiktok.com`
  - Facebook → `facebed.com`
  - Reddit → `vxreddit.com`
  - Bluesky → `bskx.app`
- **Platform Support** - X/Twitter, Instagram, TikTok, Reddit, Bluesky, Threads, YouTube (including Shorts), Facebook, LinkedIn, Substack, GitHub, Discord, Pinterest, Snapchat, Spotify, Amazon, eBay, AliExpress, and more
- **Discord Cleanup** - Normalizes `canary.discord.com` and `ptb.discord.com` links to `discord.com`
- **Google Search Extraction** - Pulls the actual destination URL from Google Search redirect links
- **Redirect Detection** - Follows redirect chains (e.g. email click-trackers like `ctrk.klclick.com`, URL shorteners) to the final destination and cleans that URL too; requires an internet connection - basic cleaning still works fully offline
- **History** - Keeps a local log of cleaned URLs with page titles fetched automatically for easier identification; supports per-entry deletion
- **QR Code** - Generate a QR code for any cleaned URL with one click
- **Themes** - Multiple color themes to choose from
- **PWA** - Installable as a progressive web app, works offline, and appears in your system share sheet so you can send URLs directly from other apps

## How to Use

1. Paste a URL into the input field (or use the clipboard paste button)
2. Click **Clean URL** (or press Enter)
3. Copy, open, share, or generate a **QR code** for the cleaned result
4. Use **View History** to revisit previously cleaned URLs (titles load automatically)

You can also pass a URL via query string:

```text
https://fixup.uwuapps.org/?url=https://example.com/...
https://fixup.uwuapps.org/?link=https://example.com/...
```

Or share any URL directly to the app from your device's share menu (requires the PWA to be installed).
