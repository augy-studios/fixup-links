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
from handlers.core import build_fix_keyboard, build_fix_view, do_fix
from reply import send_rich_message

log = logging.getLogger('bot.autodetect')


async def autodetect_message(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Fixes up to three links in a group message and replies with each
    result, unless autodetect is off for the chat or a link was already clean."""
    message = update.effective_message
    chat = update.effective_chat
    if not message or not message.text:
        return

    db_connection = context.bot_data['db']
    await db.touch_chat(db_connection, chat.id, default_autodetect=config.AUTODETECT_DEFAULT)

    enabled = await db.get_autodetect_enabled(db_connection, chat.id, default_autodetect=config.AUTODETECT_DEFAULT)
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
        only_already_clean = True
        for change in result.changes:
            if change.type != 'clean':
                only_already_clean = False
                break
        if only_already_clean:
            continue

        fix_id = await db.add_fix_result(
            db_connection, chat_id=chat.id, requester_id=update.effective_user.id,
            original_url=raw_link, cleaned_url=cleaned, platform=result.platform,
        )
        await db.add_history(db_connection, user_id=update.effective_user.id, original_url=raw_link,
                              cleaned_url=cleaned, platform=result.platform)

        rich = build_fix_view(raw_link, cleaned, result, title)
        keyboard = build_fix_keyboard(fix_id, cleaned)
        await send_rich_message(context.bot, chat.id, rich, keyboard, reply_to=message.message_id)
