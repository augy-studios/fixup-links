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

chips = []
for m in re.finditer(r'<div class="platform-chip">(.*?)</div>', card, re.S):
    inner = m.group(1)
    svg = re.search(r'<svg.*?</svg>', inner, re.S).group(0)
    svg = re.sub(r'\s+', ' ', svg).replace('> <', '><')
    if 'xmlns' not in svg:
        svg = svg.replace('<svg ', '<svg xmlns="http://www.w3.org/2000/svg" ', 1)
    text = re.sub(r'<svg.*?</svg>', '', inner, flags=re.S)
    note = re.search(r'<span class="chip-note">(.*?)</span>', text, re.S)
    name = re.sub(r'<span class="chip-note">.*?</span>', '', text, flags=re.S)
    name = html.unescape(re.sub(r'\s+', ' ', name).strip())
    chips.append({'name': name, 'note': html.unescape(note.group(1).strip()) if note else '', 'svg': svg})

out = ['// Written by tool/platforms_from_site.py from main-site/index.html\'s Supported Platforms card.',
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
for c in chips:
    out.append(f"  PlatformChip({json.dumps(c['name'])}, {json.dumps(c['note'])},")
    out.append(f"      {json.dumps(c['svg'])}),")
out.append('];')
dart = '\n'.join(out).replace('$', '\\$') + '\n'
open(os.path.join(root, 'lib', 'data', 'platforms.dart'), 'w', encoding='utf-8', newline='\n').write(dart)
print(len(chips), 'chips')
