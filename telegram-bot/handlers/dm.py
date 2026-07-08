"""Private-chat text handling: /fix and /batch follow-up replies, and
implicit auto-fix when a link is sent to the bot with no command at all.

This is intentionally a single handler rather than three separate
MessageHandlers. PTB only runs the *first* matching handler within a given
handler group, and fix.capture_awaited_link / batch.capture_awaited_batch
used to be registered as separate handlers in the same group with
identical (always-true) filters - so the batch follow-up handler could
never actually fire, since the fix follow-up handler always matched first
and won. Checking both user_data flags in sequence here avoids that trap
entirely.
"""
from __future__ import annotations

import linkfix
from telegram import Update
from telegram.ext import ContextTypes

from handlers import batch as batch_module
from handlers import fix as fix_module

AUTOFIX_LIMIT = 3


async def handle_private_text(update: Update, context: ContextTypes.DEFAULT_TYPE):
    message = update.effective_message
    text = (message.text or '').strip()

    if context.user_data.pop(fix_module.AWAITING_FIX_KEY, False):
        urls = linkfix.find_urls(text)
        raw_link = urls[0] if urls else text
        await fix_module._send_fix_result(update, context, raw_link, reply_to=message.message_id)
        return

    if context.user_data.pop(batch_module.AWAITING_BATCH_KEY, False):
        await batch_module._run_batch(update, context, text)
        return

    urls = linkfix.find_urls(text)
    if not urls:
        return

    for raw_link in urls[:AUTOFIX_LIMIT]:
        await fix_module._send_fix_result(update, context, raw_link, reply_to=message.message_id)
