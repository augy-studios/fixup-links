"""Telegram Rich Message helpers (Bot API 10.1+: sendRichMessage and the
rich_message parameter of editMessageText), so headings, bullet lists and
tables render natively instead of being approximated with parse_mode HTML.

python-telegram-bot 22.x targets Bot API 10.0 and has no wrapper for these
yet, so the requests go through its raw request layer. Every helper falls
back to a plain-text send/edit if the rich request is rejected (old Bot API
server, malformed markdown, ...) and logs why - a rich failure never
surfaces as an unhandled error.

Message contract: every builder that produces structured content returns
    rich = {'markdown': <Rich Markdown string>, 'fallback': <plain text>}
`markdown` is what current clients render; `fallback` is what gets sent if
the rich request fails. Never leave `fallback` empty. See handlers/core.py
for the escaping helpers that dynamic data must go through.
"""
from __future__ import annotations

import logging

from telegram import Bot, CallbackQuery, InputMessageContent, Message, ReplyParameters
from telegram.error import BadRequest

log = logging.getLogger('bot.reply')


def _rich_markdown(rich: dict) -> dict:
    """The InputRichMessage object for a rich dict."""
    return {'markdown': rich['markdown']}


def _reply_parameters(reply_to: int | None) -> ReplyParameters | None:
    if reply_to is None:
        return None
    return ReplyParameters(message_id=reply_to, allow_sending_without_reply=True)


def _is_not_modified(err: Exception) -> bool:
    """Editing a message with identical content and keyboard is a BadRequest
    ("Message is not modified") - harmless, e.g. paging to the same page."""
    return isinstance(err, BadRequest) and 'not modified' in str(err).lower()


def rich_input_content(rich: dict) -> InputMessageContent:
    """InputRichMessageContent for an inline query result, so a chosen result
    is delivered as a real rich message (InputTextMessageContent can't carry one)."""
    return InputMessageContent(api_kwargs={'rich_message': _rich_markdown(rich)})


def sent_message_id(result) -> int | None:
    """Id of the message a rich send created, for storing and editing later
    with edit_rich_message_at."""
    return result.message_id if isinstance(result, Message) else None


async def send_rich_message(bot: Bot, chat_id: int, rich: dict, buttons=None, *, reply_to: int | None = None) -> Message:
    data = {
        'chat_id': chat_id,
        'rich_message': _rich_markdown(rich),
        'reply_markup': buttons,
        'reply_parameters': _reply_parameters(reply_to),
    }
    try:
        return await bot.do_api_request('sendRichMessage', api_kwargs=data, return_type=Message)
    except Exception as err:
        log.warning('[send_rich_message] rich send failed, falling back: %s', err)
        return await bot.send_message(
            chat_id, rich['fallback'], reply_markup=buttons, reply_parameters=_reply_parameters(reply_to),
        )


async def _edit_rich(bot: Bot, target: dict, rich: dict, buttons) -> None:
    """Shared raw editMessageText call. `target` is either
    {'chat_id', 'message_id'} or {'inline_message_id'}.

    Bot._post rather than Bot.do_api_request because the latter warns whenever
    PTB already has a wrapper for the endpoint, and Bot.edit_message_text
    can't be used since it insists on `text`, which must be left out when
    `rich_message` is given.

    An omitted reply_markup removes the existing inline keyboard in the Bot API
    (unlike MTProto), so "no buttons" really does mean no keyboard.
    """
    await bot._post('editMessageText', {**target, 'rich_message': _rich_markdown(rich), 'reply_markup': buttons})


async def edit_rich_message_at(bot: Bot, chat_id: int, msg_id: int, rich: dict, buttons=None) -> None:
    """Edit by chat + message id. No buttons => keyboard removed."""
    try:
        await _edit_rich(bot, {'chat_id': chat_id, 'message_id': msg_id}, rich, buttons)
    except Exception as err:
        if _is_not_modified(err):
            return
        log.warning('[edit_rich_message_at] rich edit failed, falling back: %s', err)
        try:
            await bot.edit_message_text(rich['fallback'], chat_id=chat_id, message_id=msg_id, reply_markup=buttons)
        except BadRequest as fallback_err:
            if not _is_not_modified(fallback_err):
                raise


async def edit_rich_message(bot: Bot, query: CallbackQuery, rich: dict, buttons=None) -> None:
    """Edit the message a CallbackQuery came from - regular chat or inline-mode."""
    if query.inline_message_id:
        target = {'inline_message_id': query.inline_message_id}
    else:
        target = {'chat_id': query.message.chat.id, 'message_id': query.message.message_id}
    try:
        await _edit_rich(bot, target, rich, buttons)
    except Exception as err:
        if _is_not_modified(err):
            return
        log.warning('[edit_rich_message] rich edit failed, falling back: %s', err)
        try:
            await bot.edit_message_text(rich['fallback'], **target, reply_markup=buttons)
        except BadRequest as fallback_err:
            if not _is_not_modified(fallback_err):
                raise
