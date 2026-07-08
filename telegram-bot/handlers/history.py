"""/history command - lets a user page back through their own fixed links."""
from __future__ import annotations

from html import escape

from telegram import InlineKeyboardButton, InlineKeyboardMarkup, Update
from telegram.ext import ContextTypes

import db

PAGE_SIZE = 5
CB_NAV = 'hn'


def _build_history_text(rows, page: int) -> str:
    lines = [f'<b>Your link history</b> (page {page})', '']
    if not rows:
        lines.append('Nothing here yet. Fix a link with /fix to get started.')
        return '\n'.join(lines)
    for row in rows:
        platform = escape(row['platform'] or 'General')
        original = escape(row['original_url'][:200])
        cleaned = escape(row['cleaned_url'][:200])
        lines.append(f'<b>{platform}</b>\n{original}\n→ {cleaned}\n')
    return '\n'.join(lines)


def _build_nav_keyboard(user_id: int, page: int, has_more: bool) -> InlineKeyboardMarkup:
    buttons = [
        InlineKeyboardButton('Previous', callback_data=f'{CB_NAV}:{user_id}:{page - 1}', ) if page > 1
        else InlineKeyboardButton(' ', callback_data='noop'),
        InlineKeyboardButton('Next', callback_data=f'{CB_NAV}:{user_id}:{page + 1}') if has_more
        else InlineKeyboardButton(' ', callback_data='noop'),
    ]
    return InlineKeyboardMarkup([buttons])


async def history_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user = update.effective_user
    rows, has_more = await db.get_history_page(context.bot_data['db'], user.id, 0, PAGE_SIZE)
    text = _build_history_text(rows, 1)
    keyboard = _build_nav_keyboard(user.id, 1, has_more)
    await update.effective_message.reply_text(text, parse_mode='HTML', reply_markup=keyboard)


async def history_nav_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    _, uid_s, page_s = query.data.split(':')
    owner_id, page = int(uid_s), max(int(page_s), 1)

    if query.from_user.id != owner_id:
        await query.answer("This isn't your history to page through.", show_alert=True)
        return

    offset = (page - 1) * PAGE_SIZE
    rows, has_more = await db.get_history_page(context.bot_data['db'], owner_id, offset, PAGE_SIZE)
    text = _build_history_text(rows, page)
    keyboard = _build_nav_keyboard(owner_id, page, has_more)
    await query.edit_message_text(text, parse_mode='HTML', reply_markup=keyboard)
    await query.answer()


async def noop_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.callback_query.answer()
