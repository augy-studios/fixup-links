"""/fix command plus the QR / toggle / refresh / delete buttons on its result.

Buttons carry only a fix_results row id in their callback_data (see
handlers/core.py), so they keep working after a bot restart as long as the
row is still in SQLite - there is no in-memory state to lose.
"""
from __future__ import annotations

import io
import logging

import qrcode
from telegram import InputFile, Update
from telegram.ext import ContextTypes, filters

import db
import linkfix
from handlers.core import (
    CB_DELETE, CB_QR, CB_REFRESH, CB_TOGGLE,
    build_fix_keyboard, do_fix, format_fix_message,
)

log = logging.getLogger('bot.fix')

AWAITING_FIX_KEY = 'awaiting_fix_link'


async def _send_fix_result(update: Update, context: ContextTypes.DEFAULT_TYPE, raw_link: str, *, reply_to=None):
    db_conn = context.bot_data['db']
    chat = update.effective_chat
    user = update.effective_user

    try:
        result, cleaned, title = await do_fix(context.bot_data['http_session'], raw_link)
    except linkfix.InvalidUrlError as e:
        await context.bot.send_message(chat.id, str(e), reply_to_message_id=reply_to)
        return

    fix_id = await db.add_fix_result(
        db_conn, chat_id=chat.id, requester_id=user.id,
        original_url=raw_link, cleaned_url=cleaned, platform=result.platform,
    )
    await db.add_history(db_conn, user_id=user.id, original_url=raw_link,
                          cleaned_url=cleaned, platform=result.platform)

    text = format_fix_message(raw_link, cleaned, result, title)
    keyboard = build_fix_keyboard(fix_id, cleaned)
    await context.bot.send_message(
        chat.id, text, parse_mode='HTML', reply_markup=keyboard,
        reply_to_message_id=reply_to, disable_web_page_preview=False,
    )


async def fix_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if context.args:
        raw_link = ' '.join(context.args)
        await _send_fix_result(update, context, raw_link, reply_to=update.effective_message.message_id)
        return

    context.user_data[AWAITING_FIX_KEY] = True
    await update.effective_message.reply_text('Send me the link you want fixed.')


async def capture_awaited_link(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not context.user_data.pop(AWAITING_FIX_KEY, False):
        return
    text = (update.effective_message.text or '').strip()
    urls = linkfix.find_urls(text)
    raw_link = urls[0] if urls else text
    await _send_fix_result(update, context, raw_link, reply_to=update.effective_message.message_id)


awaiting_link_filter = filters.TEXT & ~filters.COMMAND


async def qr_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    fix_id = int(query.data.split(':', 1)[1])
    row = await db.get_fix_result(context.bot_data['db'], fix_id)
    if not row:
        await query.answer('This result has expired.', show_alert=True)
        return
    img = qrcode.make(row['cleaned_url'])
    buf = io.BytesIO()
    img.save(buf, format='PNG')
    buf.seek(0)
    await query.answer()
    await context.bot.send_photo(
        query.message.chat.id, InputFile(buf, filename='qr.png'),
        reply_to_message_id=query.message.message_id,
    )


async def toggle_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    fix_id = int(query.data.split(':', 1)[1])
    db_conn = context.bot_data['db']
    row = await db.get_fix_result(db_conn, fix_id)
    if not row:
        await query.answer('This result has expired.', show_alert=True)
        return

    showing_original = not bool(row['showing_original'])
    await db.update_fix_result(db_conn, fix_id, showing_original=showing_original)

    result = linkfix.clean_url(row['original_url']) if showing_original else None
    text = format_fix_message(
        row['original_url'], row['cleaned_url'],
        result or linkfix.CleanResult(cleaned=row['cleaned_url'], platform=row['platform']),
        None, showing_original=showing_original,
    )
    keyboard = build_fix_keyboard(fix_id, row['cleaned_url'], showing_original=showing_original)
    await query.edit_message_text(text, parse_mode='HTML', reply_markup=keyboard)
    await query.answer()


async def refresh_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    fix_id = int(query.data.split(':', 1)[1])
    db_conn = context.bot_data['db']
    row = await db.get_fix_result(db_conn, fix_id)
    if not row:
        await query.answer('This result has expired.', show_alert=True)
        return

    try:
        result, cleaned, title = await do_fix(context.bot_data['http_session'], row['original_url'])
    except linkfix.InvalidUrlError:
        await query.answer('That link is no longer valid.', show_alert=True)
        return

    await db.update_fix_result(db_conn, fix_id, cleaned_url=cleaned, platform=result.platform, showing_original=False)
    text = format_fix_message(row['original_url'], cleaned, result, title)
    keyboard = build_fix_keyboard(fix_id, cleaned)
    await query.edit_message_text(text, parse_mode='HTML', reply_markup=keyboard)
    await query.answer('Refreshed.')


async def delete_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    fix_id = int(query.data.split(':', 1)[1])
    row = await db.get_fix_result(context.bot_data['db'], fix_id)

    allowed = bool(row) and row['requester_id'] == query.from_user.id
    if not allowed and query.message.chat.type in ('group', 'supergroup'):
        member = await context.bot.get_chat_member(query.message.chat.id, query.from_user.id)
        allowed = member.status in ('administrator', 'creator')

    if not allowed:
        await query.answer("Only the person who requested this can delete it.", show_alert=True)
        return

    await query.message.delete()
    await query.answer()


CALLBACK_HANDLERS = {
    CB_QR: qr_callback,
    CB_TOGGLE: toggle_callback,
    CB_REFRESH: refresh_callback,
    CB_DELETE: delete_callback,
}
