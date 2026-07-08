"""Group autodetect: watches group messages for links that are worth fixing
(have trackers, or have a supported embed-friendly domain swap) and replies
automatically. Per-chat opt-out is stored in SQLite via /settings.

Requires the bot's privacy mode to be disabled in BotFather (/setprivacy)
so it can see message text it wasn't directly addressed with - see README.
"""
from __future__ import annotations

import logging

from telegram import Update
from telegram.ext import ContextTypes

import config
import db
import linkfix
from handlers.core import build_fix_keyboard, do_fix, format_fix_message

log = logging.getLogger('bot.autodetect')


async def autodetect_message(update: Update, context: ContextTypes.DEFAULT_TYPE):
    message = update.effective_message
    chat = update.effective_chat
    if not message or not message.text:
        return

    db_conn = context.bot_data['db']
    await db.touch_chat(db_conn, chat.id, default_autodetect=config.AUTODETECT_DEFAULT)

    enabled = await db.get_autodetect_enabled(db_conn, chat.id, default_autodetect=config.AUTODETECT_DEFAULT)
    if not enabled:
        return

    urls = linkfix.find_urls(message.text)
    if not urls:
        return

    for raw_link in urls[:3]:
        try:
            result, cleaned, title = await do_fix(context.bot_data['http_session'], raw_link)
        except linkfix.InvalidUrlError:
            continue

        # Only reply when the fix actually did something worth showing.
        if all(c.type == 'clean' for c in result.changes):
            continue

        fix_id = await db.add_fix_result(
            db_conn, chat_id=chat.id, requester_id=update.effective_user.id,
            original_url=raw_link, cleaned_url=cleaned, platform=result.platform,
        )
        await db.add_history(db_conn, user_id=update.effective_user.id, original_url=raw_link,
                              cleaned_url=cleaned, platform=result.platform)

        text = format_fix_message(raw_link, cleaned, result, title)
        keyboard = build_fix_keyboard(fix_id, cleaned)
        await message.reply_text(text, parse_mode='HTML', reply_markup=keyboard)
