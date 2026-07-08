"""/batch command - fix several links at once."""
from __future__ import annotations

import re
from html import escape

from telegram import InlineKeyboardButton, InlineKeyboardMarkup, Update
from telegram.ext import ContextTypes

import config
import db
import linkfix
from handlers.core import CB_COPYALL, do_fix

AWAITING_BATCH_KEY = 'awaiting_batch_links'


def _build_copyall_keyboard(batch_id: int) -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup([[InlineKeyboardButton('Copy all', callback_data=f'{CB_COPYALL}:{batch_id}')]])


async def _run_batch(update: Update, context: ContextTypes.DEFAULT_TYPE, links_text: str):
    db_conn = context.bot_data['db']
    chat = update.effective_chat
    user = update.effective_user

    urls = [u for u in re.split(r'\s+', links_text.strip()) if u]
    urls = urls[:config.MAX_BATCH_LINKS]

    if not urls:
        await update.effective_message.reply_text('No links found in that input.')
        return

    lines = []
    cleaned_urls = []
    for original in urls:
        try:
            result, cleaned, _title = await do_fix(context.bot_data['http_session'], original)
        except linkfix.InvalidUrlError:
            lines.append(f'<s>{escape(original)}</s> (invalid URL)')
            continue

        await db.add_fix_result(db_conn, chat_id=chat.id, requester_id=user.id,
                                 original_url=original, cleaned_url=cleaned, platform=result.platform)
        await db.add_history(db_conn, user_id=user.id, original_url=original,
                              cleaned_url=cleaned, platform=result.platform)
        cleaned_urls.append(cleaned)
        lines.append(f'<b>{escape(result.platform)}</b>\n{escape(original)}\n→ {escape(cleaned)}')

    header = f'<b>Fixed {len(cleaned_urls)}/{len(urls)} links</b>\n\n'
    body = '\n\n'.join(lines)
    text = (header + body)[:4000]

    keyboard = None
    if cleaned_urls:
        batch_id = await db.add_batch_result(db_conn, chat_id=chat.id, requester_id=user.id, cleaned_urls=cleaned_urls)
        keyboard = _build_copyall_keyboard(batch_id)

    await update.effective_message.reply_text(text, parse_mode='HTML', reply_markup=keyboard)


async def batch_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if context.args:
        await _run_batch(update, context, ' '.join(context.args))
        return
    context.user_data[AWAITING_BATCH_KEY] = True
    await update.effective_message.reply_text('Send me the links to clean, one per line or separated by spaces.')


async def copyall_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    batch_id = int(query.data.split(':', 1)[1])
    row = await db.get_batch_result(context.bot_data['db'], batch_id)
    if not row:
        await query.answer('This batch result has expired.', show_alert=True)
        return
    content = f"<code>{escape(row['cleaned_urls'])}</code>"
    if len(content) > 4000:
        content = content[:3990] + '…</code>'
    await query.answer()
    await context.bot.send_message(query.message.chat.id, content, parse_mode='HTML',
                                    reply_to_message_id=query.message.message_id)
