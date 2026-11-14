"""Writes the update files the desktop apps read (lib/desktop/updater.dart), in the Electron
updater's format, for the installers in a folder:

  latest.yml              Windows: uwufix-<v>-setup.exe
  latest-mac.yml          macOS: both .zip files (and the .dmg files, for completeness)
  latest-linux.yml        Linux x64: the x86_64 AppImage
  latest-linux-arm64.yml  Linux arm64: the arm64 AppImage

    python installers/write_latest_yml.py <version> <folder>
"""
import base64
import datetime
import hashlib
import os
import sys

version, folder = sys.argv[1], sys.argv[2]
now = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.000Z')


def entry(name):
    path = os.path.join(folder, name)
    h = hashlib.sha512()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return {'url': name, 'sha512': base64.b64encode(h.digest()).decode(), 'size': os.path.getsize(path)}


def write(yml, names):
    names = [n for n in names if os.path.exists(os.path.join(folder, n))]
    if not names:
        return
    files = [entry(n) for n in names]
    lines = [f'version: {version}', 'files:']
    for f in files:
        lines += [f"  - url: {f['url']}", f"    sha512: {f['sha512']}", f"    size: {f['size']}"]
    lines += [f"path: {files[0]['url']}", f"sha512: {files[0]['sha512']}", f"releaseDate: '{now}'"]
    with open(os.path.join(folder, yml), 'w', newline='\n') as out:
        out.write('\n'.join(lines) + '\n')
    print('wrote', yml, 'for', ', '.join(names))


v = version
write('latest.yml', [f'uwufix-{v}-setup.exe'])
write('latest-mac.yml', [f'uwufix-{v}-mac-arm64.zip', f'uwufix-{v}-mac-x64.zip', f'uwufix-{v}-mac-arm64.dmg', f'uwufix-{v}-mac-x64.dmg'])
write('latest-linux.yml', [f'uwufix-{v}-x86_64.AppImage'])
write('latest-linux-arm64.yml', [f'uwufix-{v}-arm64.AppImage'])
