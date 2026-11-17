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
from handlers.core import code_cell, escape_cell, markdown_table
from reply import edit_rich_message, send_rich_message

PAGE_SIZE = 5
CALLBACK_NAVIGATION = 'hn'
CALLBACK_DELETE_ENTRY = 'hd'
CALLBACK_CLEAR = 'hc'
CALLBACK_CLEAR_CONFIRM = 'hcc'
CALLBACK_CLEAR_CANCEL = 'hcx'

EMPTY_TEXT = 'Nothing here yet. Fix a link with /fix to get started.'


def build_history_view(rows, page: int) -> dict:
    """Row numbers are the labels on the delete buttons, so they must stay 1-based per page."""
    heading = 'Your link history'
    markdown_lines = [f'# {heading}', f'_Page {page}_', '']
    plain_lines = [f'{heading} (page {page})', '']
    if not rows:
        markdown_lines.append(EMPTY_TEXT)
        plain_lines.append(EMPTY_TEXT)
        return {'markdown': '\n'.join(markdown_lines), 'fallback': '\n'.join(plain_lines)}

    table_rows = []
    for row_number, row in enumerate(rows, start=1):
        platform = row['platform']
        if not platform:
            platform = 'General'
        original = row['original_url'][:200]
        cleaned = row['cleaned_url'][:200]
        table_rows.append([row_number, escape_cell(platform), code_cell(original), code_cell(cleaned)])
        plain_lines.append(f'{row_number}. {platform}\n{original}\n→ {cleaned}\n')
    markdown_lines += markdown_table(['Platform', 'Original', 'Fixed'], table_rows)
    return {'markdown': '\n'.join(markdown_lines), 'fallback': '\n'.join(plain_lines).rstrip()}


def _build_keyboard(user_id: int, page: int, rows, has_more: bool) -> InlineKeyboardMarkup | None:
    """Buttons under a history page: a numbered delete button per entry,
    Previous / Next paging, and Clear all. None when there are no buttons."""
    button_rows = []

    # One numbered delete button per entry on this page, several per row so
    # the keyboard doesn't get too tall.
    delete_buttons = []
    for row_number, row in enumerate(rows, start=1):
        delete_buttons.append(
            InlineKeyboardButton(f'🗑 {row_number}', callback_data=f'{CALLBACK_DELETE_ENTRY}:{user_id}:{row["id"]}:{page}')
        )
    for chunk_start in range(0, len(delete_buttons), 5):
        button_rows.append(delete_buttons[chunk_start:chunk_start + 5])

    navigation_row = []
    if page > 1:
        navigation_row.append(InlineKeyboardButton('◀ Previous', callback_data=f'{CALLBACK_NAVIGATION}:{user_id}:{page - 1}'))
    if has_more:
        navigation_row.append(InlineKeyboardButton('Next ▶', callback_data=f'{CALLBACK_NAVIGATION}:{user_id}:{page + 1}'))
    if navigation_row:
        button_rows.append(navigation_row)

    if rows:
        button_rows.append([InlineKeyboardButton('Clear all history', callback_data=f'{CALLBACK_CLEAR}:{user_id}')])

    if button_rows:
        return InlineKeyboardMarkup(button_rows)
    return None


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


async def history_navigation_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    _, owner_id_text, page_text = query.data.split(':')
    owner_id = int(owner_id_text)
    page = max(int(page_text), 1)

    if query.from_user.id != owner_id:
        await query.answer("This isn't your history to page through.", show_alert=True)
        return

    rich, keyboard = await _render_page(context, owner_id, page)
    await edit_rich_message(context.bot, query, rich, keyboard)
    await query.answer()


async def delete_entry_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Deletes one history entry and redraws the page (one page back if the
    current page is now empty)."""
    query = update.callback_query
    _, owner_id_text, entry_id_text, page_text = query.data.split(':')
    owner_id = int(owner_id_text)
    entry_id = int(entry_id_text)
    page = max(int(page_text), 1)

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
    _, owner_id_text = query.data.split(':')
    owner_id = int(owner_id_text)

    if query.from_user.id != owner_id:
        await query.answer("This isn't your history to clear.", show_alert=True)
        return

    keyboard = InlineKeyboardMarkup([[
        InlineKeyboardButton('Yes, delete it all', callback_data=f'{CALLBACK_CLEAR_CONFIRM}:{owner_id}'),
        InlineKeyboardButton('Cancel', callback_data=f'{CALLBACK_CLEAR_CANCEL}:{owner_id}:1'),
    ]])
    await query.edit_message_text(
        'Delete your entire link history? This can\'t be undone.',
        reply_markup=keyboard,
    )
    await query.answer()


async def clear_confirm_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    _, owner_id_text = query.data.split(':')
    owner_id = int(owner_id_text)

    if query.from_user.id != owner_id:
        await query.answer("This isn't your history to clear.", show_alert=True)
        return

    deleted = await db.clear_history(context.bot_data['db'], owner_id)
    # The now-empty page has no keyboard, so this edit also removes it.
    rich, keyboard = await _render_page(context, owner_id, 1)
    await edit_rich_message(context.bot, query, rich, keyboard)
    if deleted == 1:
        entry_word_ending = 'y'
    else:
        entry_word_ending = 'ies'
    await query.answer(f'Deleted {deleted} entr{entry_word_ending}.')


async def clear_cancel_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    _, owner_id_text, page_text = query.data.split(':')
    owner_id = int(owner_id_text)
    page = max(int(page_text), 1)

    if query.from_user.id != owner_id:
        await query.answer("This isn't your history.", show_alert=True)
        return

    rich, keyboard = await _render_page(context, owner_id, page)
    await edit_rich_message(context.bot, query, rich, keyboard)
    await query.answer()


CALLBACK_HANDLERS = {
    CALLBACK_NAVIGATION: history_navigation_callback,
    CALLBACK_DELETE_ENTRY: delete_entry_callback,
    CALLBACK_CLEAR: clear_prompt_callback,
    CALLBACK_CLEAR_CONFIRM: clear_confirm_callback,
    CALLBACK_CLEAR_CANCEL: clear_cancel_callback,
}
