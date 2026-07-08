"""Entry point. Run with: python bot.py (inside a tmux session on the VPS)."""
from __future__ import annotations

import asyncio
import logging
import os

import aiohttp
import discord
from discord.ext import commands
from dotenv import load_dotenv

from db import init_db

load_dotenv()

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(name)s: %(message)s',
)
log = logging.getLogger('bot')

TOKEN = os.environ.get('DISCORD_TOKEN')
GUILD_ID = os.environ.get('GUILD_ID') or None
DB_PATH = os.environ.get('DB_PATH', './data/uwufix_bot.sqlite3')
WEB_APP_URL = os.environ.get('WEB_APP_URL', 'https://fixup.uwuapps.org')
AUTO_DETECT = os.environ.get('AUTO_DETECT', 'true').lower() not in ('0', 'false', 'no')
MAX_BATCH_LINKS = int(os.environ.get('MAX_BATCH_LINKS', '10'))

INITIAL_EXTENSIONS = (
    'cogs.fix',
    'cogs.batch',
    'cogs.history',
    'cogs.help_cmd',
)

intents = discord.Intents.default()
intents.message_content = True


class LinkFixBot(commands.Bot):
    def __init__(self):
        # No prefix commands are used (slash commands only); the prefix is
        # required by the library but never actually triggers anything.
        super().__init__(command_prefix=commands.when_mentioned, intents=intents, help_command=None)
        self.db = None
        self.http_session: aiohttp.ClientSession | None = None
        self.web_app_url = WEB_APP_URL
        self.auto_detect_enabled = AUTO_DETECT
        self.max_batch_links = MAX_BATCH_LINKS

    async def setup_hook(self):
        self.db = await init_db(DB_PATH)
        self.http_session = aiohttp.ClientSession()

        for ext in INITIAL_EXTENSIONS:
            await self.load_extension(ext)

        if GUILD_ID:
            guild = discord.Object(id=int(GUILD_ID))
            self.tree.copy_global_to(guild=guild)
            await self.tree.sync(guild=guild)
            log.info('Synced commands to guild %s', GUILD_ID)
        else:
            await self.tree.sync()
            log.info('Synced global commands (may take up to an hour to propagate)')

    async def close(self):
        if self.http_session:
            await self.http_session.close()
        if self.db:
            await self.db.close()
        await super().close()


bot = LinkFixBot()


@bot.event
async def on_ready():
    log.info('Logged in as %s (id: %s)', bot.user, bot.user.id)


def main():
    if not TOKEN:
        raise SystemExit('DISCORD_TOKEN is not set. Copy .env.example to .env and fill it in.')
    asyncio.run(bot.start(TOKEN))


if __name__ == '__main__':
    main()
