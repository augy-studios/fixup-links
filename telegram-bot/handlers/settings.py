"""/settings command - lets a group admin (or anyone in a private chat) toggle
automatic link fixing for that chat. Preference is stored per chat_id in
SQLite so it persists across restarts.
"""
from __future__ import annotations

import config
import db
from telegram import InlineKeyboardButton, InlineKeyboardMarkup, Update
from telegram.ext import ContextTypes

CB_AUTODETECT = 'ad'


def _keyboard(enabled: bool) -> InlineKeyboardMarkup:
    label = 'Turn autodetect off' if enabled else 'Turn autodetect on'
    return InlineKeyboardMarkup([[InlineKeyboardButton(label, callback_data=f'{CB_AUTODETECT}:{int(not enabled)}')]])


async def _is_group_admin(update: Update, context: ContextTypes.DEFAULT_TYPE) -> bool:
    chat = update.effective_chat
    if chat.type not in ('group', 'supergroup'):
        return True
    member = await context.bot.get_chat_member(chat.id, update.effective_user.id)
    return member.status in ('administrator', 'creator')


async def settings_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    chat = update.effective_chat
    if not await _is_group_admin(update, context):
        await update.effective_message.reply_text('Only group admins can change these settings.')
        return

    enabled = await db.get_autodetect_enabled(context.bot_data['db'], chat.id, default_autodetect=config.AUTODETECT_DEFAULT)
    status = 'on' if enabled else 'off'
    await update.effective_message.reply_text(
        f'Automatic link fixing in this chat is currently <b>{status}</b>.\n'
        'When on, links with trackers or a fixable embed get an automatic reply.',
        parse_mode='HTML',
        reply_markup=_keyboard(enabled),
    )


async def autodetect_toggle_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    chat = query.message.chat
    if not await _is_group_admin(update, context):
        await query.answer('Only group admins can change these settings.', show_alert=True)
        return

    new_value = bool(int(query.data.split(':', 1)[1]))
    await db.set_autodetect_enabled(context.bot_data['db'], chat.id, new_value)
    status = 'on' if new_value else 'off'
    await query.edit_message_text(
        f'Automatic link fixing in this chat is now <b>{status}</b>.\n'
        'When on, links with trackers or a fixable embed get an automatic reply.',
        parse_mode='HTML',
        reply_markup=_keyboard(new_value),
    )
    await query.answer()
