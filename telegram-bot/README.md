# Link Fixer Bot (Telegram)

A Telegram bot that cleans messy links: it strips tracking parameters and
swaps in embed-friendly domains so previews actually render properly. It's
the same cleanup logic used by the [web app](https://fixup.uwuapps.org) and
the [Discord bot](../discord-bot), available in Telegram as commands, inline
results, and automatic group replies.

## Features

- **Tracker removal** - strips UTM parameters, click IDs, and platform-specific
  tracking junk (Klaviyo, Facebook, TikTok, Amazon affiliate tags, and more)
  from any URL.
- **Embed fixing** - converts links to embed-friendly domains so previews
  actually render:
  - X/Twitter, Instagram, TikTok, Facebook, Reddit, Bluesky
- **Redirect following** - follows shortened/redirected links (email
  click-trackers, `t.co`-style shorteners, etc.) to their final destination
  and cleans that too.
- **Google Search extraction** - pulls the real destination out of a Google
  Search redirect link.
- **Persistent result buttons** - every fixed link comes with **Open**,
  **Copy**, **QR code**, **Show original / Show fixed**, **Refresh**, and
  **Delete** buttons. They're backed by SQLite row ids in their
  `callback_data`, not in-memory state, so they keep working indefinitely -
  including after the bot restarts.
- **Per-user history** - the bot remembers every link it has fixed for you so
  you can page back through it later, in `/history` or inline mode. Delete
  individual entries or clear it all from `/history` itself.
- **Inline mode** - type `@uwuFix_bot <link>` in any chat to fix a link
  without adding the bot to that chat. Invoke it with no link to pick from
  your recent history instead.
- **Private-chat auto-fix** - just send a link to the bot with no command at
  all in a private chat and it fixes it automatically.
- **Group autodetect** - when enabled for a chat, links with trackers or a
  fixable embed domain get an automatic reply, no command needed.
- **Persisted per-chat settings** - autodetect on/off is stored per chat in
  SQLite, not memory.
- **Scheduled status updates** - a SQLite-backed job (survives restarts)
  periodically updates the bot's short description with how many chats it's
  active in.

Command and message text never hardcodes the bot's display name, so that
part reads correctly no matter what you register it as with BotFather. The
`@uwuFix_bot` username *is* referenced (in the inline-mode example in
`/start`), since that's functionally necessary rather than branding - it's
configurable via `BOT_USERNAME` in `.env` if you register a different one.

## Commands

### `/start`
Shows what the bot does, its full command list, and buttons linking to the
web app and the donate page.

### `/fix`
Cleans a single link. Use `/fix <url>`, or just `/fix` and then send the
link as your next message. Posts the result with Open / Copy / QR code /
Show original / Refresh / Delete buttons, the detected platform, what was
changed, and the destination page title when available. In a private chat
you don't even need the command - just sending the bot a link does the same
thing.

### `/batch`
Cleans several links in one go. Use `/batch <links>`, or `/batch` and then
send the links (one per line or separated by spaces) as your next message.
Returns a summary of each link plus a **Copy all** button.

### `/history`
Shows a paginated list of links you've previously had the bot fix, newest
first, with Previous/Next buttons - only you can page through your own
history. Each entry has its own 🗑 delete button, and a **Clear all
history** button (with a confirm/cancel step) wipes everything at once.

### `/settings`
Lets a group admin (or anyone in a private chat) turn automatic link fixing
on or off for that chat. The choice is stored in SQLite per chat.

### `/donate`
Links to the project's donation page.

### Inline mode
Type `@uwuFix_bot <link>` in any chat to get a fixed link you can send
without adding the bot to that chat. Type `@uwuFix_bot` with nothing after
it to pick from your own recent history instead of retyping a link.

### Group autodetect
When enabled for a chat (see `/settings`), messages containing a link with
trackers or a fixable embed domain get an automatic reply with the cleaned
version. Requires privacy mode to be disabled for the bot in BotFather - see
[SETUP.md](SETUP.md).

## Why SQLite shows up in a few places

- **Buttons** - `fix_results`/`batch_results`/`history` rows hold the data a
  button refers to; the button's `callback_data` only carries the row id
  (e.g. a history entry's delete button), so it works forever, independent
  of process memory.
- **Chat settings** - `/settings` (autodetect on/off) is per-chat state that
  needs to survive restarts.
- **Scheduling** - the periodic bot-description update job is registered in
  an APScheduler job store backed by SQLite (`SCHEDULER_DB_PATH`), so its
  schedule isn't lost on restart.
