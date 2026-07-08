# Setup

Instructions for registering the bot with Telegram and running it on a
Debian 13 VPS inside `tmux`.

## 1. Create the bot with BotFather

1. Open a chat with [@BotFather](https://t.me/BotFather) in Telegram and send `/newbot`.
2. Follow the prompts to pick a display name and a `@username`. Neither is
   referenced anywhere in the bot's own command text, so you're free to
   rename it later without touching the code.
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
     full command list, or use inline mode (@your_bot_username <link>)
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
- `DB_PATH`, `SCHEDULER_DB_PATH`, `WEB_APP_URL`, `DONATE_URL`,
  `MAX_BATCH_LINKS`, `AUTODETECT_DEFAULT`, `BIO_UPDATE_INTERVAL_MINUTES` -
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

## Notes

- The bot uses long polling (`run_polling`), not webhooks, so there's no
  need to open a port or configure a reverse proxy/TLS cert on the VPS.
- SQLite files live under `./data/` next to `bot.py` by default
  (`DB_PATH`, `SCHEDULER_DB_PATH`), and that directory is gitignored - back
  it up separately if you care about history/settings surviving a fresh
  `git clone`.
