"""Shared link-fixing pipeline and message/keyboard builders used by the
/fix command, /batch command, inline mode, and group autodetect - so all
four surfaces produce identical output.

Structured replies are Telegram Rich Messages (see reply.py): each builder
returns a `rich` dict of {'markdown', 'fallback'} plus its keyboard. The
markdown is Telegram's Rich Markdown dialect (GFM-compatible: `# Heading`,
`**bold**`, `_italic_`, bullet lists, pipe tables). Every piece of dynamic
data - titles, URLs, platform names, API strings - must go through
escape_markdown / escape_cell / code_span; literal markup authored here is not
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
CALLBACK_QR = 'qr'
CALLBACK_TOGGLE = 'tg'
CALLBACK_REFRESH = 'rf'
CALLBACK_DELETE = 'de'
CALLBACK_COPY_ALL = 'ca'

# Everything Telegram's Rich Markdown gives meaning to. Beyond plain GFM
# punctuation it also parses `==mark==`, `$formula$`, `![media]` and
# arbitrary inline HTML, so `<` and `&` are escaped as well - URLs are full
# of `&` and would otherwise be at the mercy of entity decoding.
_MARKDOWN_SPECIAL_CHARACTERS = re.compile(r'([\\*_~`|\[\]#>=<&$!])')


def escape_markdown(text) -> str:
    """Escape user/data text for Telegram's Rich Markdown dialect."""
    return _MARKDOWN_SPECIAL_CHARACTERS.sub(r'\\\1', str(text))


def escape_cell(text) -> str:
    """Escape for a GFM table cell; also flattens newlines so the row stays intact."""
    return escape_markdown(str(text).replace('\n', ' '))


def code_span(text) -> str:
    """Inline code for a URL or other verbatim string (monospace, tap to
    copy). Backslash escapes don't apply inside code, so a longer backtick
    fence is used instead when the text itself contains backticks."""
    text = str(text).replace('\n', ' ')
    longest = 0
    for backtick_run in re.findall(r'`+', text):
        if len(backtick_run) > longest:
            longest = len(backtick_run)
    fence = '`' * (longest + 1)
    if longest:
        padding = ' '
    else:
        padding = ''
    return f'{fence}{padding}{text}{padding}{fence}'


def code_cell(text) -> str:
    """code_span for a table cell: a pipe inside code still ends the cell
    unless escaped."""
    return code_span(text).replace('|', '\\|')


def markdown_table(headers, rows) -> list[str]:
    """Pipe table lines. The header row gets an unlabeled first column; each
    row is [label, *values] with the label (a number, a name) in it. Cell
    contents must already be escaped with escape_cell / code_cell."""
    lines = ['| ' + ' | '.join(['', *headers]) + ' |',
             '| ' + ' | '.join(['---'] * (len(headers) + 1)) + ' |']
    for row in rows:
        cell_texts = []
        for value in row:
            cell_texts.append(str(value))
        lines.append('| ' + ' | '.join(cell_texts) + ' |')
    return lines


async def do_fix(http_session, original_url: str) -> tuple[linkfix.CleanResult, str, str | None]:
    """Cleans a URL and resolves redirects/title. Returns (clean_result, final_cleaned_url, title)."""
    result = linkfix.clean_url(original_url)
    cleaned = result.cleaned

    metadata = await linkfix.resolve_url(http_session, cleaned)
    final_url = metadata.get('final_url')
    if final_url and final_url != cleaned:
        try:
            final_host = linkfix.hostname_of(urlsplit(final_url))
            cleaned_host = linkfix.hostname_of(urlsplit(cleaned))
            if final_host != cleaned_host:
                redirect_result = linkfix.clean_url(final_url)
                cleaned = redirect_result.cleaned
                result.changes.append(linkfix.Change('redirect', f'Redirects to {urlsplit(cleaned).hostname}'))
        except Exception:
            pass
    title = metadata.get('title')

    return result, cleaned, title


def build_fix_view(original_url: str, cleaned_url: str, result: linkfix.CleanResult,
                   title: str | None, *, showing_original: bool = False) -> dict:
    """The rich message for one fixed link: {'markdown', 'fallback'}."""
    if showing_original:
        shown_url = original_url
        heading = 'Original link'
    else:
        shown_url = cleaned_url
        heading = 'Link fixed'
    change_labels = []
    for change in result.changes:
        change_labels.append(change.label)
    changes_text = ', '.join(change_labels)
    if not changes_text:
        changes_text = 'None'
    if not title:
        title = ''
    title = title.strip()

    markdown_lines = [f'# {heading}']
    if title:
        markdown_lines.append(f'_{escape_markdown(title)}_')
    markdown_lines += ['', code_span(shown_url), '',
           f'- **Platform:** {escape_markdown(result.platform)}',
           f'- **Changes:** {escape_markdown(changes_text)}']

    plain_lines = [heading]
    if title:
        plain_lines.append(title)
    plain_lines += ['', shown_url, '', f'Platform: {result.platform}', f'Changes: {changes_text}']

    return {'markdown': '\n'.join(markdown_lines), 'fallback': '\n'.join(plain_lines)}


def build_fix_keyboard(fix_id: int, cleaned_url: str, *, showing_original: bool = False) -> InlineKeyboardMarkup:
    """Buttons under a fixed link: Open, Copy, QR code, Show original/fixed,
    Refresh and Delete."""
    if not showing_original:
        toggle_label = 'Show original'
    else:
        toggle_label = 'Show fixed'
    rows = [
        [InlineKeyboardButton('Open', url=cleaned_url)],
        [
            InlineKeyboardButton('Copy', copy_text=CopyTextButton(text=cleaned_url[:256])),
            InlineKeyboardButton('QR code', callback_data=f'{CALLBACK_QR}:{fix_id}'),
        ],
        [
            InlineKeyboardButton(
                toggle_label,
                callback_data=f'{CALLBACK_TOGGLE}:{fix_id}',
            ),
            InlineKeyboardButton('Refresh', callback_data=f'{CALLBACK_REFRESH}:{fix_id}'),
        ],
        [InlineKeyboardButton('Delete', callback_data=f'{CALLBACK_DELETE}:{fix_id}')],
    ]
    return InlineKeyboardMarkup(rows)
