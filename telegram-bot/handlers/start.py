"""/start, /donate - informational commands. The bot's own display name is
never referenced in this text, but its @username is (config.BOT_USERNAME) -
that's needed so the inline-mode example is actually usable, and unlike a
display name it can't be swapped without breaking real functionality."""
from __future__ import annotations

from telegram import InlineKeyboardButton, InlineKeyboardMarkup, Update
from telegram.ext import ContextTypes

import config
import db
from handlers.core import code_span
from reply import send_rich_message

_INTRO = (
    'Strips tracking parameters from links and swaps in embed-friendly domains '
    'so previews actually render (X/Twitter, Instagram, TikTok, Facebook, Reddit, '
    'Bluesky, and more).'
)
_DM_HINT = (
    'In a private chat with the bot, you can also just send a link with no '
    'command at all and it gets fixed automatically.'
)
_COMMANDS = [
    ('/fix', 'clean a single link'),
    ('/batch', 'clean several links at once'),
    ('/history', 'browse, delete, or clear links you have fixed before'),
    ('/settings', 'turn automatic link fixing on/off for this chat (group admins)'),
    ('/donate', 'support the project'),
]
_INLINE_HINT = (
    'in any chat to fix a link without adding the bot, or with nothing after '
    'the @mention to pick from your recent history.'
)
_GROUPS_HINT = (
    'Post a link with trackers or a fixable embed domain and, if enabled for that '
    'chat, it gets fixed automatically.'
)


def build_info_view() -> dict:
    inline_example = f'@{config.BOT_USERNAME} <link>'
    md = [
        '# Link cleaning and embed fixing',
        _INTRO, '', _DM_HINT, '',
        '## Commands',
        *[f'- {cmd} — {what}' for cmd, what in _COMMANDS],
        '',
        '## Inline mode',
        f'Type {code_span(inline_example)} {_INLINE_HINT}', '',
        '## In groups',
        _GROUPS_HINT,
    ]
    plain = [
        'Link cleaning and embed fixing',
        _INTRO, '', _DM_HINT, '',
        'Commands',
        *[f'{cmd} - {what}' for cmd, what in _COMMANDS],
        '',
        'Inline mode',
        f'Type {inline_example} {_INLINE_HINT}', '',
        'In groups',
        _GROUPS_HINT,
    ]
    return {'markdown': '\n'.join(md), 'fallback': '\n'.join(plain)}


def _footer_keyboard() -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup([
        [InlineKeyboardButton('Open web app', url=config.WEB_APP_URL)],
        [InlineKeyboardButton('Discord bot', url=config.DISCORD_INVITE_URL)],
        [InlineKeyboardButton('Donate', url=config.DONATE_URL)],
    ])


async def start_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    chat = update.effective_chat
    await db.touch_chat(context.bot_data['db'], chat.id, default_autodetect=config.AUTODETECT_DEFAULT)
    await send_rich_message(context.bot, chat.id, build_info_view(), _footer_keyboard(),
                            reply_to=update.effective_message.message_id)


async def donate_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.effective_message.reply_text(
        'If this bot saves you a click or two, you can chip in here:',
        reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton('Donate', url=config.DONATE_URL)]]),
    )
