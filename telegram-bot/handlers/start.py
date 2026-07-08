"""/start, /donate - informational commands. The bot's own display name is
never referenced in this text, but its @username is (config.BOT_USERNAME) -
that's needed so the inline-mode example is actually usable, and unlike a
display name it can't be swapped without breaking real functionality."""
from __future__ import annotations

from telegram import InlineKeyboardButton, InlineKeyboardMarkup, Update
from telegram.ext import ContextTypes

import config
import db


def _info_text() -> str:
    return (
        '<b>Link cleaning &amp; embed fixing</b>\n'
        "Strips tracking parameters from links and swaps in embed-friendly domains "
        "so previews actually render (X/Twitter, Instagram, TikTok, Facebook, Reddit, "
        "Bluesky, and more).\n\n"
        'In a private chat with the bot, you can also just send a link with no '
        'command at all and it gets fixed automatically.\n\n'
        '<b>Commands</b>\n'
        '/fix - clean a single link\n'
        '/batch - clean several links at once\n'
        '/history - browse links you have fixed before\n'
        '/settings - turn automatic link fixing on/off for this chat (group admins)\n'
        '/donate - support the project\n\n'
        '<b>Inline mode</b>\n'
        f'Type <code>@{config.BOT_USERNAME} &lt;link&gt;</code> in any chat to fix a link '
        'without adding the bot, or with nothing after the @mention to pick from your '
        'recent history.\n\n'
        '<b>In groups</b>\n'
        'Post a link with trackers or a fixable embed domain and, if enabled for that '
        'chat, it gets fixed automatically.'
    )


def _footer_keyboard() -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup([
        [InlineKeyboardButton('Open web app', url=config.WEB_APP_URL)],
        [InlineKeyboardButton('Discord bot', url=config.DISCORD_INVITE_URL)],
        [InlineKeyboardButton('Donate', url=config.DONATE_URL)],
    ])


async def start_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    chat = update.effective_chat
    await db.touch_chat(context.bot_data['db'], chat.id, default_autodetect=config.AUTODETECT_DEFAULT)
    await update.effective_message.reply_text(_info_text(), parse_mode='HTML', reply_markup=_footer_keyboard())


async def donate_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.effective_message.reply_text(
        'If this bot saves you a click or two, you can chip in here:',
        reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton('Donate', url=config.DONATE_URL)]]),
    )
