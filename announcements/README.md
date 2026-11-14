# Announcements

What's said about each release, kept in one place, as sgbus-timings keeps its own:

| File | Where it goes |
|---|---|
| `release-notes-<version>.md` | The GitHub release's description (release/README.md, "Put it on GitHub") |
| `announcement-<version>.md` | A post in the UwU Apps Telegram channel, as it is |
| `play-release-notes-<version>.md` | Google Play's **Release notes** box, from 1.1.0 (GOOGLE-PLAY.md) |

## Language

Everything here is in British English (en-GB): colour, optimised, licence, Wi-Fi, and dates as
14 November 2026. Play's notes go in an `<en-GB>` block, the store listing's default language.

## Writing the release notes

The Android app's updates page (flutter/android/.../UpdateActivity.java) shows every release's
notes as cards, read through main-site/api/_release.js's `notesOf`, so keep to this shape:

```markdown
One paragraph: what this release is about. It's the card's summary.

## Download
(a table of the files)

## Updating
(how, per platform)

## What's new

### Android app
- **Title**: what it does, for the person using it.

### Desktop apps
- **Title**: ...

### Everywhere
- **Title**: ...

## What's fixed
- **Title**: ...
```

Each `###` under **What's new** becomes a card, its icon picked from its heading (Android, desktop,
history, look, notifications, ...), and each `- **Title**: text` a row in it. Plain words: no
links or code needed inside the items.

## Writing the announcement

Short lines a phone shows whole: the version, the site, what's new as dashes, then the download
link. No Markdown; Telegram shows it as it is.

## Writing Play's notes

At most 500 characters per language, between `<en-GB>` and `</en-GB>` tags (one block per language
the listing has). Only what the Play build has: it has no updater of its own, so nothing about
updating.
