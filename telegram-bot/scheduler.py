"""Periodic jobs, persisted in SQLite so the schedule survives bot restarts
(mirrors the Discord bot's presence update, since Telegram bots have no
equivalent live-presence push - instead we periodically rewrite the bot's
short description with a stat, driven by an APScheduler job whose schedule
lives in its own SQLite-backed jobstore).
"""
from __future__ import annotations

import logging

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.jobstores.sqlalchemy import SQLAlchemyJobStore

import config
import db

log = logging.getLogger('bot.scheduler')

scheduler = AsyncIOScheduler(
    jobstores={'default': SQLAlchemyJobStore(url=f'sqlite:///{config.SCHEDULER_DB_PATH}')},
)


async def _update_bio(application):
    try:
        chat_count = await db.count_known_chats(application.bot_data['db'])
        text = f'Cleaning links in {chat_count} chat{"s" if chat_count != 1 else ""}.'
        await application.bot.set_my_short_description(short_description=text[:120])
    except Exception:
        log.exception('Failed to update bot short description')


def start(application):
    scheduler.add_job(
        _update_bio,
        'interval',
        minutes=config.BIO_UPDATE_INTERVAL_MINUTES,
        args=[application],
        id='update_bio',
        replace_existing=True,
    )
    scheduler.start()
    log.info('Scheduler started (bio update every %s minutes)', config.BIO_UPDATE_INTERVAL_MINUTES)
