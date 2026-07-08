# Setup

Instructions for registering the bot with Telegram and running it on a
Debian 13 VPS inside `tmux`.

## 1. Create the bot with BotFather

1. Open a chat with [@BotFather](https://t.me/BotFather) in Telegram and send `/newbot`.
2. Follow the prompts to pick a display name and a `@username`. The display
   name is never referenced anywhere in the bot's own command text, so you're
   free to rename it later without touching the code. The `@username` is
   used in one place - the inline-mode example shown in `/start` - via
   `BOT_USERNAME` in `.env`. This repo is set up for `@uwuFix_bot`; if you
   register a different username, update `BOT_USERNAME` to match (see step 3
   of "Configure the bot" below).
3. BotFather replies with a token - copy it. Keep this secret; it goes in
   `.env` (`BOT_TOKEN`), which is already gitignored.
4. **Enable inline mode**: send `/setinline` to BotFather, pick your bot,
   and give it a placeholder text (e.g. `Paste a link to fix...`).
5. **Disable privacy mode** (required for group autodetect to see message
   text it wasn't directly addressed with): send `/setprivacy` to BotFather,
   pick your bot, and choose **Disable**. If you don't need group
   autodetect, you can leave privacy mode on and skip this - commands and
   inline mode work either way.
6. **Set the description and about text.** Telegram bots have two separate
   blurbs, and BotFather has a command for each:
   - `/setdescription` sets the **long description** (up to 512 characters),
     shown on the empty chat screen before someone taps **Start**, and in
     link previews when the bot is shared. The bot never touches this, so
     it's safe to set once. Suggested text:

     ```text
     Cleans messy links: strips tracking parameters and swaps in
     embed-friendly domains (X/Twitter, Instagram, TikTok, Facebook,
     Reddit, Bluesky) so previews actually render. Send /start for the
     full command list, or use inline mode (@uwuFix_bot <link>)
     in any chat.
     ```

   - `/setabouttext` sets the **short description / about text** (up to
     120 characters), shown on the bot's profile page above the **Start**
     button. **Don't bother customizing this one** - the bot overwrites it
     itself on a schedule (`_update_bio` in `scheduler.py`, every
     `BIO_UPDATE_INTERVAL_MINUTES`) with a live count of how many chats
     it's active in, e.g. `Cleaning links in 12 chats.`, mirroring the
     Discord bot's presence status. Whatever you set with `/setabouttext`
     will be replaced the first time that job runs after the bot starts.

   For both commands, send them to BotFather, pick your bot, then paste the
   text when prompted.
7. **Set the `/` command menu.** The bot does *not* push its own command
   list in code - this is managed entirely through BotFather, so it's set
   once and doesn't need a network call on every startup. Send
   `/setcommands` to BotFather, pick your bot, then paste:

   ```text
   start - Show what this bot does
   fix - Clean a single link
   batch - Clean several links at once
   history - Browse, delete, or clear links you have fixed before
   settings - Toggle automatic link fixing for this chat
   donate - Support the project
   ```

   If you add, rename, or remove a command in `bot.py` later, update this
   list with `/setcommands` again to keep the `/` menu in sync - it isn't
   done automatically. This is currently the bot's full command set; there's
   nothing else registered in `bot.py` to add here.

   `/history` itself doesn't need a separate command - deleting entries and
   clearing history are done with buttons under the `/history` reply (a 🗑
   button per entry, plus a **Clear all history** button with a
   confirm/cancel step), not extra commands. Those buttons carry a SQLite
   row id in their `callback_data` (see `handlers/history.py`), so they keep
   working indefinitely, including across bot restarts - nothing to
   configure for this in BotFather or `.env`.

## 2. Install dependencies on the VPS (Debian 13)

```bash
sudo apt update
sudo apt install -y python3 python3-venv python3-pip git tmux

git clone <your-repo-url>
cd fixup-links/telegram-bot

python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

## 3. Configure the bot

```bash
cp .env.example .env
nano .env
```

Fill in:

- `BOT_TOKEN` - the token from step 1.3
- `BOT_USERNAME` - already set to `uwuFix_bot`; only change this if you
  registered a different `@username` with BotFather in step 1.2
- `DB_PATH`, `SCHEDULER_DB_PATH`, `WEB_APP_URL`, `DONATE_URL`,
  `DISCORD_INVITE_URL`, `MAX_BATCH_LINKS`, `AUTODETECT_DEFAULT`,
  `BIO_UPDATE_INTERVAL_MINUTES` -
  sensible defaults are already filled in; adjust if needed.

## 4. Run it in tmux

```bash
tmux new -s linkfixbot
cd fixup-links/telegram-bot
source venv/bin/activate
python bot.py
```

Detach with `Ctrl+B` then `D` - the bot keeps running. To reattach later:

```bash
tmux attach -t linkfixbot
```

To check it's alive without attaching:

```bash
tmux ls
```

## 5. Updating

```bash
tmux attach -t linkfixbot
# Ctrl+C to stop the bot
git pull
source venv/bin/activate
pip install -r requirements.txt   # only if requirements.txt changed
python bot.py
```

## Troubleshooting: "Timed out" on startup

If `python bot.py` fails immediately with something like:

```text
[ERROR] telegram.ext: Network Retry Loop (Bootstrap Initialize Application): Timed out: Timed out.
```

this is happening before any of the bot's own code runs - it's the library's
very first call to Telegram (`getMe`) failing to get a response over HTTPS
from `api.telegram.org`. It is **not** related to `/setcommands` or anything
else configured in BotFather. It means the VPS itself can't reach Telegram's
servers quickly enough. To diagnose:

1. Check basic connectivity from the VPS:

   ```bash
   curl -v --max-time 10 https://api.telegram.org
   ```

   If this hangs or fails, the problem is network-level, not the bot.

2. Common causes:
   - The VPS's hosting provider or country blocks/throttles Telegram at the
     network level (known to happen with some providers/regions - Telegram
     is blocked outright in a few countries).
   - A firewall (`ufw`/`iptables`, or a provider-level security group) is
     blocking outbound HTTPS (port 443).
   - Transient DNS or routing issues - try `dig api.telegram.org` and
     `ping api.telegram.org` to compare.

3. If outbound access to Telegram is blocked or unreliable from the VPS,
   route through a proxy: set `TELEGRAM_PROXY_URL` in `.env` (e.g.
   `socks5://user:pass@host:1080` or `http://host:8080`) and re-run. If
   using a `socks5://` proxy, make sure `pip install -r requirements.txt`
   has been re-run after pulling the latest `requirements.txt` (it installs
   the `socks` extra needed for SOCKS proxy support).
4. If it's just slow rather than fully blocked, `bot.py` already uses
   30-second connect/read timeouts (up from the library's 5-second
   default), which is usually enough headroom for a flaky but working
   connection.

## Notes

- The bot uses long polling (`run_polling`), not webhooks, so there's no
  need to open a port or configure a reverse proxy/TLS cert on the VPS.
- SQLite files live under `./data/` next to `bot.py` by default
  (`DB_PATH`, `SCHEDULER_DB_PATH`), and that directory is gitignored - back
  it up separately if you care about history/settings surviving a fresh
  `git clone`.
