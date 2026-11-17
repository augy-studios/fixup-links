"""Writes lib/data/platforms.dart from the site's Supported Platforms card (main-site/index.html):
each chip's name, its note (such as "(tracking removal)") and its icon's SVG, so the app's card is
the site's. test/platforms_test.dart fails when the two differ.

    python tool/platforms_from_site.py      (from flutter/; again whenever the card changes)
"""
import html
import json
import os
import re

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(here)
page = open(os.path.join(root, '..', 'main-site', 'index.html'), encoding='utf-8').read()
card = page[page.index('<div class="platforms-grid">'):page.index('<!-- History Button -->')]


def find_chips(card):
    """Every chip in the card, in order: its name, its note ('' if it has none) and its icon's SVG
    squeezed onto one line, given an xmlns if it has none."""
    chips = []
    for chip_match in re.finditer(r'<div class="platform-chip">(.*?)</div>', card, re.S):
        inner = chip_match.group(1)
        svg = re.search(r'<svg.*?</svg>', inner, re.S).group(0)
        svg = re.sub(r'\s+', ' ', svg).replace('> <', '><')
        if 'xmlns' not in svg:
            svg = svg.replace('<svg ', '<svg xmlns="http://www.w3.org/2000/svg" ', 1)
        text = re.sub(r'<svg.*?</svg>', '', inner, flags=re.S)
        note_match = re.search(r'<span class="chip-note">(.*?)</span>', text, re.S)
        name = re.sub(r'<span class="chip-note">.*?</span>', '', text, flags=re.S)
        name = html.unescape(re.sub(r'\s+', ' ', name).strip())
        if note_match:
            note = html.unescape(note_match.group(1).strip())
        else:
            note = ''
        chips.append({'name': name, 'note': note, 'svg': svg})
    return chips


chips = find_chips(card)

lines = ['// Written by tool/platforms_from_site.py from main-site/index.html\'s Supported Platforms card.',
         '// Don\'t edit by hand: change the site, then run the tool.',
         '',
         'class PlatformChip {',
         '  const PlatformChip(this.name, this.note, this.svg);',
         '  final String name;',
         '  final String note;',
         '  final String svg;',
         '}',
         '',
         'const platformChips = <PlatformChip>[']
for chip in chips:
    lines.append(f"  PlatformChip({json.dumps(chip['name'])}, {json.dumps(chip['note'])},")
    lines.append(f"      {json.dumps(chip['svg'])}),")
lines.append('];')
# Dart reads $ in a string as interpolation, so each one is escaped.
dart = '\n'.join(lines).replace('$', '\\$') + '\n'
open(os.path.join(root, 'lib', 'data', 'platforms.dart'), 'w', encoding='utf-8', newline='\n').write(dart)
print(len(chips), 'chips')
