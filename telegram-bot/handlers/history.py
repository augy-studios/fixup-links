"""/history command - lets a user page back through their own fixed links,
delete individual entries, or clear all of it. Every history row's SQLite
id is used directly in its delete button's callback_data, so a button
keeps pointing at the right row for as long as it exists - restart-proof,
same pattern as the fix_results buttons in handlers/core.py.
"""
from __future__ import annotations

from telegram import InlineKeyboardButton, InlineKeyboardMarkup, Update
from telegram.ext import ContextTypes

import db
from handlers.core import code_cell, escape_cell, md_table
from reply import edit_rich_message, send_rich_message

PAGE_SIZE = 5
CB_NAV = 'hn'
CB_DELETE_ENTRY = 'hd'
CB_CLEAR = 'hc'
CB_CLEAR_CONFIRM = 'hcc'
CB_CLEAR_CANCEL = 'hcx'

EMPTY_TEXT = 'Nothing here yet. Fix a link with /fix to get started.'


def build_history_view(rows, page: int) -> dict:
    """Row numbers are the labels on the delete buttons, so they must stay 1-based per page."""
    heading = 'Your link history'
    md = [f'# {heading}', f'_Page {page}_', '']
    plain = [f'{heading} (page {page})', '']
    if not rows:
        md.append(EMPTY_TEXT)
        plain.append(EMPTY_TEXT)
        return {'markdown': '\n'.join(md), 'fallback': '\n'.join(plain)}

    table_rows = []
    for i, row in enumerate(rows, start=1):
        platform = row['platform'] or 'General'
        original = row['original_url'][:200]
        cleaned = row['cleaned_url'][:200]
        table_rows.append([i, escape_cell(platform), code_cell(original), code_cell(cleaned)])
        plain.append(f'{i}. {platform}\n{original}\n→ {cleaned}\n')
    md += md_table(['Platform', 'Original', 'Fixed'], table_rows)
    return {'markdown': '\n'.join(md), 'fallback': '\n'.join(plain).rstrip()}


def _build_keyboard(user_id: int, page: int, rows, has_more: bool) -> InlineKeyboardMarkup | None:
    button_rows = []

    # One numbered delete button per entry on this page, several per row so
    # the keyboard doesn't get too tall.
    delete_buttons = [
        InlineKeyboardButton(f'🗑 {i}', callback_data=f'{CB_DELETE_ENTRY}:{user_id}:{row["id"]}:{page}')
        for i, row in enumerate(rows, start=1)
    ]
    for chunk_start in range(0, len(delete_buttons), 5):
        button_rows.append(delete_buttons[chunk_start:chunk_start + 5])

    nav_row = []
    if page > 1:
        nav_row.append(InlineKeyboardButton('◀ Previous', callback_data=f'{CB_NAV}:{user_id}:{page - 1}'))
    if has_more:
        nav_row.append(InlineKeyboardButton('Next ▶', callback_data=f'{CB_NAV}:{user_id}:{page + 1}'))
    if nav_row:
        button_rows.append(nav_row)

    if rows:
        button_rows.append([InlineKeyboardButton('Clear all history', callback_data=f'{CB_CLEAR}:{user_id}')])

    return InlineKeyboardMarkup(button_rows) if button_rows else None


async def _render_page(context: ContextTypes.DEFAULT_TYPE, user_id: int, page: int):
    offset = (page - 1) * PAGE_SIZE
    rows, has_more = await db.get_history_page(context.bot_data['db'], user_id, offset, PAGE_SIZE)
    rich = build_history_view(rows, page)
    keyboard = _build_keyboard(user_id, page, rows, has_more)
    return rich, keyboard


async def history_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user = update.effective_user
    rich, keyboard = await _render_page(context, user.id, 1)
    await send_rich_message(context.bot, update.effective_chat.id, rich, keyboard,
                            reply_to=update.effective_message.message_id)


async def history_nav_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    _, uid_s, page_s = query.data.split(':')
    owner_id, page = int(uid_s), max(int(page_s), 1)

    if query.from_user.id != owner_id:
        await query.answer("This isn't your history to page through.", show_alert=True)
        return

    rich, keyboard = await _render_page(context, owner_id, page)
    await edit_rich_message(context.bot, query, rich, keyboard)
    await query.answer()


async def delete_entry_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    _, uid_s, entry_id_s, page_s = query.data.split(':')
    owner_id, entry_id, page = int(uid_s), int(entry_id_s), max(int(page_s), 1)

    if query.from_user.id != owner_id:
        await query.answer("This isn't your history to delete from.", show_alert=True)
        return

    await db.delete_history_entry(context.bot_data['db'], entry_id, owner_id)

    # The page we were on may now be past the end (e.g. deleted the last
    # entry on the last page) - step back a page if so.
    offset = (page - 1) * PAGE_SIZE
    rows, has_more = await db.get_history_page(context.bot_data['db'], owner_id, offset, PAGE_SIZE)
    if not rows and page > 1:
        page -= 1

    rich, keyboard = await _render_page(context, owner_id, page)
    await edit_rich_message(context.bot, query, rich, keyboard)
    await query.answer('Deleted.')


async def clear_prompt_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    _, uid_s = query.data.split(':')
    owner_id = int(uid_s)

    if query.from_user.id != owner_id:
        await query.answer("This isn't your history to clear.", show_alert=True)
        return

    keyboard = InlineKeyboardMarkup([[
        InlineKeyboardButton('Yes, delete it all', callback_data=f'{CB_CLEAR_CONFIRM}:{owner_id}'),
        InlineKeyboardButton('Cancel', callback_data=f'{CB_CLEAR_CANCEL}:{owner_id}:1'),
    ]])
    await query.edit_message_text(
        'Delete your entire link history? This can\'t be undone.',
        reply_markup=keyboard,
    )
    await query.answer()


async def clear_confirm_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    _, uid_s = query.data.split(':')
    owner_id = int(uid_s)

    if query.from_user.id != owner_id:
        await query.answer("This isn't your history to clear.", show_alert=True)
        return

    deleted = await db.clear_history(context.bot_data['db'], owner_id)
    # The now-empty page has no keyboard, so this edit also removes it.
    rich, keyboard = await _render_page(context, owner_id, 1)
    await edit_rich_message(context.bot, query, rich, keyboard)
    await query.answer(f'Deleted {deleted} entr{"y" if deleted == 1 else "ies"}.')


async def clear_cancel_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    _, uid_s, page_s = query.data.split(':')
    owner_id, page = int(uid_s), max(int(page_s), 1)

    if query.from_user.id != owner_id:
        await query.answer("This isn't your history.", show_alert=True)
        return

    rich, keyboard = await _render_page(context, owner_id, page)
    await edit_rich_message(context.bot, query, rich, keyboard)
    await query.answer()


CALLBACK_HANDLERS = {
    CB_NAV: history_nav_callback,
    CB_DELETE_ENTRY: delete_entry_callback,
    CB_CLEAR: clear_prompt_callback,
    CB_CLEAR_CONFIRM: clear_confirm_callback,
    CB_CLEAR_CANCEL: clear_cancel_callback,
}
