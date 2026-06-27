# uwuFix - Link Fixer

Clean URLs, remove trackers, and fix embeds - all in your browser.

## Features

- **Tracker Removal** - Strips UTM parameters, click IDs, and platform-specific tracking from any URL
- **Embed Fixing** - Converts links to embed-friendly domains for better previews on Discord, Telegram, and more:
  - X/Twitter → `fixupx.com` (usernames replaced with `i`)
  - Instagram → `kkclip.com`
  - TikTok → `kktiktok.com` / `vt.kktiktok.com`
  - Facebook → `facebed.com`
  - Reddit → `vxreddit.com`
  - Bluesky → `bskx.app`
- **Platform Support** - X/Twitter, Instagram, TikTok, Reddit, Bluesky, YouTube, Facebook, LinkedIn, Substack, GitHub, Discord, Pinterest, Snapchat, and more
- **Discord Cleanup** - Normalizes `canary.discord.com` and `ptb.discord.com` links to `discord.com`
- **Google Search Extraction** - Pulls the actual destination URL from Google Search redirect links
- **History** - Keeps a local log of cleaned URLs with per-entry deletion
- **Themes** - Multiple color themes to choose from
- **PWA** - Installable as a progressive web app, works offline
- **Privacy** - All processing happens client-side. No data is sent to any server.

## How to Use

1. Paste a URL into the input field (or use the clipboard paste button)
2. Click **Clean URL** (or press Enter)
3. Copy, open, or share the cleaned result
4. Use **View History** to revisit previously cleaned URLs

You can also pass a URL via query string: `https://fixup.uwuapps.org/?url=https://example.com/...`
