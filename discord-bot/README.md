# Link Fixer Bot

A Discord bot that cleans messy links: it strips tracking parameters and
swaps in embed-friendly domains so previews actually render properly in
Discord. It's the same cleanup logic used by the [web app](https://fixup.uwuapps.org),
available directly as slash commands.

## Features

- **Tracker removal** - strips UTM parameters, click IDs, and platform-specific
  tracking junk (Klaviyo, Facebook, TikTok, Amazon affiliate tags, and more)
  from any URL.
- **Embed fixing** - converts links to embed-friendly domains so Discord
  actually shows a preview:
  - X/Twitter, Instagram, TikTok, Facebook, Reddit, Bluesky
- **Redirect following** - follows shortened/redirected links (email
  click-trackers, `t.co`-style shorteners, etc.) to their final destination
  and cleans that too.
- **Google Search extraction** - pulls the real destination out of a Google
  Search redirect link.
- **Persistent result buttons** - every fixed link comes with **Open**,
  **Copy**, and **QR Code** buttons that keep working indefinitely.
- **Per-user history** - the bot remembers every link you've had it fix so
  you can page back through them later.

## Commands

### `/fix link:<url>`
Cleans a single link and posts the result with **Open** / **Copy** / **QR Code**
buttons. Shows which platform was detected, what was changed, and the page
title of the destination when available.

### `/batch links:<urls>`
Cleans several links in one go. Paste them one per line or separated by
spaces. Returns a summary of each link plus a **Copy All** button to grab
every cleaned link at once.

### `/history`
Shows a private, paginated list of links you've previously had the bot fix,
newest first. Use the **Previous** / **Next** buttons to page through it —
only you can page through your own history.

### `/help`
Shows a quick rundown of everything above plus a link to the web app.
