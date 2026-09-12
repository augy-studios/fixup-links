"""Inline mode: typing @botusername <link> in any chat fixes it on the fly.
Typing @botusername with no link (or a partial, non-URL query) instead shows
the user's own recent history so they can pick a previous fix without
retyping the link.
"""
from __future__ import annotations

import uuid

from telegram import (
    CopyTextButton, InlineKeyboardButton, InlineKeyboardMarkup, InlineQueryResultArticle,
    InlineQueryResultsButton, InputTextMessageContent, Update,
)
from telegram.ext import ContextTypes

import db
import linkfix
from handlers.core import build_fix_view, do_fix
from reply import rich_input_content

HISTORY_RESULTS = 15


def _details_keyboard(cleaned_url: str) -> InlineKeyboardMarkup:
    # Only stateless buttons: an inline-mode message has no chat or
    # fix_results row for the QR / toggle / refresh callbacks to work with.
    return InlineKeyboardMarkup([[
        InlineKeyboardButton('Open', url=cleaned_url),
        InlineKeyboardButton('Copy', copy_text=CopyTextButton(text=cleaned_url[:256])),
    ]])


def _looks_like_url(text: str) -> bool:
    return bool(linkfix.find_urls(text)) or text.strip().count('.') >= 1


async def _history_results(context: ContextTypes.DEFAULT_TYPE, user_id: int):
    rows, _ = await db.get_history_page(context.bot_data['db'], user_id, 0, HISTORY_RESULTS)
    results = []
    for row in rows:
        results.append(
            InlineQueryResultArticle(
                id=str(uuid.uuid4()),
                title=f"{row['platform'] or 'General'} - {row['cleaned_url'][:60]}",
                description=row['original_url'][:80],
                input_message_content=InputTextMessageContent(row['cleaned_url']),
            )
        )
    return results


async def inline_query(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.inline_query
    text = (query.query or '').strip()

    if not text:
        results = await _history_results(context, query.from_user.id)
        button_text = 'Your recent fixes' if results else 'Type or paste a link to fix'
        await query.answer(
            results,
            cache_time=0,
            is_personal=True,
            button=InlineQueryResultsButton(text=button_text, start_parameter='inline_help'),
        )
        return

    if not _looks_like_url(text):
        await query.answer(
            [], cache_time=0, is_personal=True,
            button=InlineQueryResultsButton(text='Paste a link to fix it', start_parameter='inline_help'),
        )
        return

    try:
        result, cleaned, title = await do_fix(context.bot_data['http_session'], text)
    except linkfix.InvalidUrlError:
        await query.answer(
            [], cache_time=0, is_personal=True,
            button=InlineQueryResultsButton(text="That doesn't look like a valid link", start_parameter='inline_help'),
        )
        return

    await db.add_history(context.bot_data['db'], user_id=query.from_user.id,
                          original_url=text, cleaned_url=cleaned, platform=result.platform)

    description = title or ', '.join(c.label for c in result.changes)
    # First result sends just the URL (so the chat gets its link preview);
    # the second sends the same rich card /fix produces.
    link_article = InlineQueryResultArticle(
        id=str(uuid.uuid4()),
        title=f'{result.platform}: send fixed link',
        description=description,
        input_message_content=InputTextMessageContent(cleaned),
    )
    details_article = InlineQueryResultArticle(
        id=str(uuid.uuid4()),
        title=f'{result.platform}: send fix details',
        description=cleaned[:80],
        input_message_content=rich_input_content(build_fix_view(text, cleaned, result, title)),
        reply_markup=_details_keyboard(cleaned),
    )
    await query.answer([link_article, details_article], cache_time=0, is_personal=True)
