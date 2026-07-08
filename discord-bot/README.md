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
- **Automatic detection** - if you post a link in chat that has trackers or
  a fixable embed, the bot replies with a **Fix Link** button so you don't
  even need to run a command. These buttons never expire, even across bot
  restarts.
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

### Automatic link fixing
You don't have to use a command at all — just post a link normally. If the
bot detects trackers or a platform it knows how to convert to an
embed-friendly domain, it replies with a **Fix Link** button. Clicking it
sends you a private result with the same Open/Copy/QR options as `/fix`.
Links that are already clean are left alone, so the bot won't comment on
every single link posted.
