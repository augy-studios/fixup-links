# Setup

Instructions for getting the bot registered with Discord and running on a
Debian 13 VPS inside `tmux`.

## 1. Create the Discord application & bot

1. Go to the [Discord Developer Portal](https://discord.com/developers/applications) and click **New Application**. Give it any name — this name is just how it shows up in Discord's UI, it's not referenced by any of the bot's commands.
2. Open the **Bot** tab, click **Reset Token** / **Add Bot**, then click **Reset Token** to reveal and copy the bot token. Keep this secret — it goes in `.env` (`DISCORD_TOKEN`), which is already gitignored.
3. On the same **Bot** tab, scroll to **Privileged Gateway Intents** and enable:
   - **Message Content Intent** — required so the bot can read message text and auto-detect links posted in chat. Without this, `/fix`, `/batch`, and `/history` still work, but automatic link detection will not.
4. Under **Installation** (or **OAuth2 → URL Generator** on older portal layouts):
   - **Scopes**: check `bot` and `applications.commands`
   - **Bot Permissions**: check
     - Send Messages
     - Send Messages in Threads
     - Embed Links
     - Attach Files (needed for the QR code button)
     - Read Message History
     - Use Slash Commands (usually implied by `applications.commands`)
   - Copy the generated invite URL and open it in a browser to add the bot to your server.

## 2. Install dependencies on the VPS (Debian 13)

```bash
sudo apt update
sudo apt install -y python3 python3-venv python3-pip git tmux

git clone <your-repo-url>
cd fixup-links/discord-bot

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
- `DISCORD_TOKEN` — the token from step 1.2
- `GUILD_ID` — optional; set this to your server's ID while testing so slash commands sync instantly (right-click your server icon → Copy Server ID, with Developer Mode enabled in Discord). Leave blank for a global sync when you're ready for production (can take up to an hour to propagate to all servers).
- `DB_PATH`, `WEB_APP_URL`, `AUTO_DETECT`, `MAX_BATCH_LINKS` — sensible defaults are already filled in; adjust if needed.

## 4. Run it in tmux

```bash
tmux new -s linkfixbot
cd fixup-links/discord-bot
source venv/bin/activate
python bot.py
```

Detach with `Ctrl+B` then `D` — the bot keeps running. To reattach later:

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
