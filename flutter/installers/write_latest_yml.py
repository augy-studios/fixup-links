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

version = sys.argv[1]
folder = sys.argv[2]
now = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.000Z')


def entry(name):
    """One file's entry in an update file: its name, its SHA-512 (base64, as Electron's updater
    has it) and its size in bytes."""
    path = os.path.join(folder, name)
    hasher = hashlib.sha512()
    with open(path, 'rb') as file:
        # A megabyte at a time, so a large installer isn't read into memory whole.
        while True:
            chunk = file.read(1 << 20)
            if chunk == b'':
                break
            hasher.update(chunk)
    return {'url': name, 'sha512': base64.b64encode(hasher.digest()).decode(), 'size': os.path.getsize(path)}


def write(yml, names):
    """Writes the update file `yml` for those of the named files that are in the folder; the
    first one found is the one the updater downloads. Writes nothing if none are there."""
    present_names = []
    for name in names:
        if os.path.exists(os.path.join(folder, name)):
            present_names.append(name)
    if not present_names:
        return
    files = []
    for name in present_names:
        files.append(entry(name))
    lines = [f'version: {version}', 'files:']
    for file_entry in files:
        lines += [f"  - url: {file_entry['url']}", f"    sha512: {file_entry['sha512']}", f"    size: {file_entry['size']}"]
    lines += [f"path: {files[0]['url']}", f"sha512: {files[0]['sha512']}", f"releaseDate: '{now}'"]
    with open(os.path.join(folder, yml), 'w', newline='\n') as output:
        output.write('\n'.join(lines) + '\n')
    print('wrote', yml, 'for', ', '.join(present_names))


write('latest.yml', [f'uwufix-{version}-setup.exe'])
write('latest-mac.yml', [f'uwufix-{version}-mac-arm64.zip', f'uwufix-{version}-mac-x64.zip',
                         f'uwufix-{version}-mac-arm64.dmg', f'uwufix-{version}-mac-x64.dmg'])
write('latest-linux.yml', [f'uwufix-{version}-x86_64.AppImage'])
write('latest-linux-arm64.yml', [f'uwufix-{version}-arm64.AppImage'])
