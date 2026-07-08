"""Periodic jobs, persisted in SQLite so the schedule survives bot restarts
(mirrors the Discord bot's presence update, since Telegram bots have no
equivalent live-presence push - instead we periodically rewrite the bot's
short description with a stat, driven by an APScheduler job whose schedule
lives in its own SQLite-backed jobstore).

Job args must stay pickle-able (SQLAlchemyJobStore pickles them to persist
the job), so this deliberately avoids passing the live Application/Bot
object around - it takes the bot token and db path (plain strings) and
builds short-lived Bot/DB objects inside the job itself.
"""
from __future__ import annotations

import logging

import aiosqlite
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.jobstores.sqlalchemy import SQLAlchemyJobStore
from telegram import Bot

import config
import db

log = logging.getLogger('bot.scheduler')

scheduler = AsyncIOScheduler(
    jobstores={'default': SQLAlchemyJobStore(url=f'sqlite:///{config.SCHEDULER_DB_PATH}')},
)


async def _update_bio(bot_token: str, db_path: str):
    try:
        conn = await aiosqlite.connect(db_path)
        conn.row_factory = aiosqlite.Row
        try:
            chat_count = await db.count_known_chats(conn)
        finally:
            await conn.close()

        text = f'Cleaning links in {chat_count} chat{"s" if chat_count != 1 else ""}.'
        bot = Bot(token=bot_token)
        async with bot:
            await bot.set_my_short_description(short_description=text[:120])
    except Exception:
        log.exception('Failed to update bot short description')


def start():
    scheduler.add_job(
        _update_bio,
        'interval',
        minutes=config.BIO_UPDATE_INTERVAL_MINUTES,
        args=[config.BOT_TOKEN, config.DB_PATH],
        id='update_bio',
        replace_existing=True,
    )
    scheduler.start()
    log.info('Scheduler started (bio update every %s minutes)', config.BIO_UPDATE_INTERVAL_MINUTES)
