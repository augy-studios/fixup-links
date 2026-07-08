"""Entry point. Run with: python bot.py (inside a tmux session on the VPS)."""
from __future__ import annotations

import logging

import aiohttp
from telegram import Update
from telegram.ext import (
    Application, CallbackQueryHandler, CommandHandler, InlineQueryHandler,
    MessageHandler, filters,
)

import config
import db
import scheduler as scheduler_module
from handlers import autodetect, batch, fix, history, inline, settings, start
from handlers.core import CB_COPYALL

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(name)s: %(message)s',
)
log = logging.getLogger('bot')

# The bot's / command menu is set manually in BotFather (/setcommands), not
# here - see SETUP.md. Keeping it out of code avoids clobbering whatever is
# configured there on every restart, and avoids a startup network call that
# can time out before the bot is otherwise ready to serve.


async def post_init(application: Application):
    application.bot_data['db'] = await db.init_db(config.DB_PATH)
    application.bot_data['http_session'] = aiohttp.ClientSession()
    scheduler_module.start(application)
    log.info('Bot ready.')


async def post_shutdown(application: Application):
    session = application.bot_data.get('http_session')
    if session:
        await session.close()
    conn = application.bot_data.get('db')
    if conn:
        await conn.close()
    if scheduler_module.scheduler.running:
        scheduler_module.scheduler.shutdown(wait=False)


async def route_callback(update: Update, context):
    query = update.callback_query
    if query.data == 'noop':
        await history.noop_callback(update, context)
        return

    prefix = query.data.split(':', 1)[0]
    if prefix in fix.CALLBACK_HANDLERS:
        await fix.CALLBACK_HANDLERS[prefix](update, context)
    elif prefix == CB_COPYALL:
        await batch.copyall_callback(update, context)
    elif prefix == history.CB_NAV:
        await history.history_nav_callback(update, context)
    elif prefix == settings.CB_AUTODETECT:
        await settings.autodetect_toggle_callback(update, context)
    else:
        await query.answer()


def main():
    if not config.BOT_TOKEN:
        raise SystemExit('BOT_TOKEN is not set. Copy .env.example to .env and fill it in.')

    builder = (
        Application.builder()
        .token(config.BOT_TOKEN)
        .connect_timeout(30)
        .read_timeout(30)
        .get_updates_connect_timeout(30)
        .get_updates_read_timeout(30)
        .post_init(post_init)
        .post_shutdown(post_shutdown)
    )
    if config.TELEGRAM_PROXY_URL:
        builder = builder.proxy(config.TELEGRAM_PROXY_URL).get_updates_proxy(config.TELEGRAM_PROXY_URL)
    application = builder.build()

    application.add_handler(CommandHandler('start', start.start_command))
    application.add_handler(CommandHandler('help', start.help_command))
    application.add_handler(CommandHandler('donate', start.donate_command))
    application.add_handler(CommandHandler('fix', fix.fix_command))
    application.add_handler(CommandHandler('batch', batch.batch_command))
    application.add_handler(CommandHandler('history', history.history_command))
    application.add_handler(CommandHandler('settings', settings.settings_command))

    # Follow-up plain-text messages for /fix and /batch when used with no
    # arguments (private chats only - group text goes through autodetect).
    application.add_handler(
        MessageHandler(filters.TEXT & ~filters.COMMAND & filters.ChatType.PRIVATE, fix.capture_awaited_link),
        group=0,
    )
    application.add_handler(
        MessageHandler(filters.TEXT & ~filters.COMMAND & filters.ChatType.PRIVATE, batch.capture_awaited_batch),
        group=0,
    )

    # Group/supergroup autodetect (requires privacy mode disabled via BotFather).
    application.add_handler(
        MessageHandler(filters.TEXT & ~filters.COMMAND & filters.ChatType.GROUPS, autodetect.autodetect_message),
        group=1,
    )

    application.add_handler(InlineQueryHandler(inline.inline_query))
    application.add_handler(CallbackQueryHandler(route_callback))

    log.info('Starting polling...')
    application.run_polling(allowed_updates=Update.ALL_TYPES)


if __name__ == '__main__':
    main()
