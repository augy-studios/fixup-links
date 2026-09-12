"""/batch command - fix several links at once."""
from __future__ import annotations

import re
from html import escape

from telegram import InlineKeyboardButton, InlineKeyboardMarkup, Update
from telegram.ext import ContextTypes

import config
import db
import linkfix
from handlers.core import CB_COPYALL, code_cell, do_fix, escape_cell, md_table
from reply import send_rich_message

AWAITING_BATCH_KEY = 'awaiting_batch_links'


def _build_copyall_keyboard(batch_id: int) -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup([[InlineKeyboardButton('Copy all', callback_data=f'{CB_COPYALL}:{batch_id}')]])


def build_batch_view(entries: list[tuple[str, str | None, str | None]], fixed_count: int) -> dict:
    """entries are (original, platform, cleaned) in input order; platform and
    cleaned are None for an invalid URL. Row numbers match the input order so
    a bad link can be found again."""
    heading = f'Fixed {fixed_count}/{len(entries)} links'

    rows = []
    plain = [heading, '']
    for i, (original, platform, cleaned) in enumerate(entries, start=1):
        if cleaned is None:
            rows.append([i, '—', f'~~{code_cell(original)}~~ invalid URL'])
            plain.append(f'{i}. {original} (invalid URL)')
        else:
            rows.append([i, escape_cell(platform), code_cell(cleaned)])
            plain.append(f'{i}. {platform}\n{original}\n→ {cleaned}')
        plain.append('')

    md = [f'# {heading}', '', *md_table(['Platform', 'Fixed link'], rows)]
    # Plain text is capped at 4096 by Telegram; the rich payload allows far more.
    return {'markdown': '\n'.join(md), 'fallback': '\n'.join(plain).rstrip()[:4000]}


async def _run_batch(update: Update, context: ContextTypes.DEFAULT_TYPE, links_text: str):
    db_conn = context.bot_data['db']
    chat = update.effective_chat
    user = update.effective_user

    urls = [u for u in re.split(r'\s+', links_text.strip()) if u]
    urls = urls[:config.MAX_BATCH_LINKS]

    if not urls:
        await update.effective_message.reply_text('No links found in that input.')
        return

    entries = []
    cleaned_urls = []
    for original in urls:
        try:
            result, cleaned, _title = await do_fix(context.bot_data['http_session'], original)
        except linkfix.InvalidUrlError:
            entries.append((original, None, None))
            continue

        await db.add_fix_result(db_conn, chat_id=chat.id, requester_id=user.id,
                                 original_url=original, cleaned_url=cleaned, platform=result.platform)
        await db.add_history(db_conn, user_id=user.id, original_url=original,
                              cleaned_url=cleaned, platform=result.platform)
        cleaned_urls.append(cleaned)
        entries.append((original, result.platform, cleaned))

    rich = build_batch_view(entries, len(cleaned_urls))

    keyboard = None
    if cleaned_urls:
        batch_id = await db.add_batch_result(db_conn, chat_id=chat.id, requester_id=user.id, cleaned_urls=cleaned_urls)
        keyboard = _build_copyall_keyboard(batch_id)

    await send_rich_message(context.bot, chat.id, rich, keyboard, reply_to=update.effective_message.message_id)


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
