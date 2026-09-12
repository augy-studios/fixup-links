"""Shared link-fixing pipeline and message/keyboard builders used by the
/fix command, /batch command, inline mode, and group autodetect - so all
four surfaces produce identical output.

Structured replies are Telegram Rich Messages (see reply.py): each builder
returns a `rich` dict of {'markdown', 'fallback'} plus its keyboard. The
markdown is Telegram's Rich Markdown dialect (GFM-compatible: `# Heading`,
`**bold**`, `_italic_`, bullet lists, pipe tables). Every piece of dynamic
data - titles, URLs, platform names, API strings - must go through
escape_md / escape_cell / code_span; literal markup authored here is not
escaped.
"""
from __future__ import annotations

import re
from urllib.parse import urlsplit

from telegram import CopyTextButton, InlineKeyboardButton, InlineKeyboardMarkup

import linkfix

# callback_data prefixes. Each carries only a small integer row id from
# fix_results/batch_results, so buttons stay valid forever - including after
# a bot restart - as long as the SQLite row they point to still exists.
CB_QR = 'qr'
CB_TOGGLE = 'tg'
CB_REFRESH = 'rf'
CB_DELETE = 'de'
CB_COPYALL = 'ca'

# Everything Telegram's Rich Markdown gives meaning to. Beyond plain GFM
# punctuation it also parses `==mark==`, `$formula$`, `![media]` and
# arbitrary inline HTML, so `<` and `&` are escaped as well - URLs are full
# of `&` and would otherwise be at the mercy of entity decoding.
_MD_SPECIAL = re.compile(r'([\\*_~`|\[\]#>=<&$!])')


def escape_md(text) -> str:
    """Escape user/data text for Telegram's Rich Markdown dialect."""
    return _MD_SPECIAL.sub(r'\\\1', str(text))


def escape_cell(text) -> str:
    """Escape for a GFM table cell; also flattens newlines so the row stays intact."""
    return escape_md(str(text).replace('\n', ' '))


def code_span(text) -> str:
    """Inline code for a URL or other verbatim string (monospace, tap to
    copy). Backslash escapes don't apply inside code, so a longer backtick
    fence is used instead when the text itself contains backticks."""
    text = str(text).replace('\n', ' ')
    longest = max((len(run) for run in re.findall(r'`+', text)), default=0)
    fence = '`' * (longest + 1)
    pad = ' ' if longest else ''
    return f'{fence}{pad}{text}{pad}{fence}'


def code_cell(text) -> str:
    """code_span for a table cell: a pipe inside code still ends the cell
    unless escaped."""
    return code_span(text).replace('|', '\\|')


def md_table(headers, rows) -> list[str]:
    """Pipe table lines. The header row gets an unlabeled first column; each
    row is [label, *values] with the label (a number, a name) in it. Cell
    contents must already be escaped with escape_cell / code_cell."""
    lines = ['| ' + ' | '.join(['', *headers]) + ' |',
             '| ' + ' | '.join(['---'] * (len(headers) + 1)) + ' |']
    for row in rows:
        lines.append('| ' + ' | '.join(str(v) for v in row) + ' |')
    return lines


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


def build_fix_view(original_url: str, cleaned_url: str, result: linkfix.CleanResult,
                   title: str | None, *, showing_original: bool = False) -> dict:
    """The rich message for one fixed link: {'markdown', 'fallback'}."""
    shown_url = original_url if showing_original else cleaned_url
    heading = 'Original link' if showing_original else 'Link fixed'
    changes_text = ', '.join(c.label for c in result.changes) or 'None'
    title = (title or '').strip()

    md = [f'# {heading}']
    if title:
        md.append(f'_{escape_md(title)}_')
    md += ['', code_span(shown_url), '',
           f'- **Platform:** {escape_md(result.platform)}',
           f'- **Changes:** {escape_md(changes_text)}']

    plain = [heading]
    if title:
        plain.append(title)
    plain += ['', shown_url, '', f'Platform: {result.platform}', f'Changes: {changes_text}']

    return {'markdown': '\n'.join(md), 'fallback': '\n'.join(plain)}


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
