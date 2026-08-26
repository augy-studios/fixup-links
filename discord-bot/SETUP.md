# Setup

Instructions for getting the bot registered with Discord and running on a
Debian 13 VPS inside `tmux`.

## 1. Create the Discord application & bot

1. Go to the [Discord Developer Portal](https://discord.com/developers/applications) and click **New Application**. Give it any name - this name is just how it shows up in Discord's UI, it's not referenced by any of the bot's commands.
2. Open the **Bot** tab, click **Reset Token** / **Add Bot**, then click **Reset Token** to reveal and copy the bot token. Keep this secret - it goes in `.env` (`DISCORD_TOKEN`), which is already gitignored.
3. Under **Installation** (or **OAuth2 → URL Generator** on older portal layouts):
   - **Scopes**: check `bot` and `applications.commands`
   - **Bot Permissions**: check
     - Send Messages
     - Send Messages in Threads
     - Embed Links
     - Attach Files (needed for the QR code button)
     - Read Message History
     - Use Slash Commands (usually implied by `applications.commands`)
   - Copy the generated invite URL and open it in a browser to add the bot to your server.
4. Still under **Installation**, set **Installation Contexts** to include both **Guild Install** and **User Install**. The commands are registered for both contexts, so if User Install is turned off here Discord rejects the command sync at startup with a 400 about integration types. User Install is also what lets `/fix` work in DMs with other people and in group DMs, not just in a DM with the bot itself.

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

- `DISCORD_TOKEN` - the token from step 1.2
- `GUILD_ID` - optional; set this to your server's ID while testing so slash commands sync instantly (right-click your server icon → Copy Server ID, with Developer Mode enabled in Discord). A global sync always runs as well - DMs and group DMs are only ever served by global commands - but that one can take up to an hour to propagate.
- `DB_PATH`, `WEB_APP_URL`, `MAX_BATCH_LINKS` - sensible defaults are already filled in; adjust if needed.

## 4. Run it in tmux

```bash
tmux new -s linkfixbot
cd fixup-links/discord-bot
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
