"""Shared link-fixing pipeline and message/keyboard builders used by the
/fix command, /batch command, inline mode, and group autodetect - so all
four surfaces produce identical output.
"""
from __future__ import annotations

from html import escape
from urllib.parse import urlsplit

from telegram import CopyTextButton, InlineKeyboardButton, InlineKeyboardMarkup

import linkfix

PARSE_MODE = 'HTML'

# callback_data prefixes. Each carries only a small integer row id from
# fix_results/batch_results, so buttons stay valid forever - including after
# a bot restart - as long as the SQLite row they point to still exists.
CB_QR = 'qr'
CB_TOGGLE = 'tg'
CB_REFRESH = 'rf'
CB_DELETE = 'de'
CB_COPYALL = 'ca'


async def do_fix(http_session, original_url: str) -> tuple[linkfix.CleanResult, str, str | None]:
    """Cleans a URL and resolves redirects/title. Returns (clean_result, final_cleaned_url, title)."""
    result = linkfix.clean_url(original_url)
    cleaned = result.cleaned

    meta = await linkfix.resolve_url(http_session, cleaned)
    final_url = meta.get('final_url')
    if final_url and final_url != cleaned:
        try:
            if (urlsplit(final_url).hostname or '') != (urlsplit(cleaned).hostname or ''):
                reresolved = linkfix.clean_url(final_url)
                cleaned = reresolved.cleaned
                result.changes.append(linkfix.Change('redirect', f'Redirects to {urlsplit(cleaned).hostname}'))
        except Exception:
            pass
    title = meta.get('title')

    return result, cleaned, title


def format_fix_message(original_url: str, cleaned_url: str, result: linkfix.CleanResult,
                        title: str | None, *, showing_original: bool = False) -> str:
    shown_url = original_url if showing_original else cleaned_url
    lines = ['<b>Original link</b>' if showing_original else '<b>Link fixed</b>']
    if title:
        lines.append(escape(title))
    lines.append('')
    lines.append(f'<code>{escape(shown_url)}</code>')
    lines.append('')
    lines.append(f'<b>Platform:</b> {escape(result.platform)}')
    changes_text = ', '.join(c.label for c in result.changes) or 'None'
    lines.append(f'<b>Changes:</b> {escape(changes_text)}')
    return '\n'.join(lines)


def build_fix_keyboard(fix_id: int, cleaned_url: str, *, showing_original: bool = False) -> InlineKeyboardMarkup:
    rows = [
        [InlineKeyboardButton('Open', url=cleaned_url)],
        [
            InlineKeyboardButton('Copy', copy_text=CopyTextButton(text=cleaned_url[:256])),
            InlineKeyboardButton('QR code', callback_data=f'{CB_QR}:{fix_id}'),
        ],
        [
            InlineKeyboardButton(
                'Show original' if not showing_original else 'Show fixed',
                callback_data=f'{CB_TOGGLE}:{fix_id}',
            ),
            InlineKeyboardButton('Refresh', callback_data=f'{CB_REFRESH}:{fix_id}'),
        ],
        [InlineKeyboardButton('Delete', callback_data=f'{CB_DELETE}:{fix_id}')],
    ]
    return InlineKeyboardMarkup(rows)
