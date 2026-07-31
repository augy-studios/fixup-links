# Link Fixer

Clean URLs, strip trackers, and swap in embed-friendly domains so link
previews actually render. This repo has three surfaces sharing the same
cleanup logic: a web app, a Discord bot, and a Telegram bot.

## Try it

- 🌐 Web app: [fixup.uwuapps.org](https://fixup.uwuapps.org)
- 💬 Discord bot: [Add to a server](https://discord.com/oauth2/authorize?client_id=1524465330091724880)
- ✈️ Telegram bot: [t.me/uwuFix_bot](https://t.me/uwuFix_bot)

| | [🌐 Web App](main-site) | [💬 Discord Bot](discord-bot) | [✈️ Telegram Bot](telegram-bot) |
|---|---|---|---|
| **What it is** | Client-side PWA at [fixup.uwuapps.org](https://fixup.uwuapps.org) | Slash-command bot for Discord servers | Command + inline bot for Telegram |
| **Use it via** | Browser, or installed as an app | `/fix`, `/batch`, `/history`, `/help` | `/fix`, `/batch`, `/history`, `/settings`, `/donate`, inline mode |
| **Tracker removal** | ✅ | ✅ | ✅ |
| **Embed-domain fixing** | ✅ | ✅ | ✅ |
| **Redirect following** | ✅ | ✅ | ✅ |
| **Google Search extraction** | ✅ | ✅ | ✅ |
| **History** | ✅ local, per-browser | ✅ per-user, paginated | ✅ per-user, paginated + inline picker, delete/clear |
| **QR codes** | ✅ | ✅ button on every result | ✅ button on every result |
| **Batch cleaning** | - | ✅ `/batch` | ✅ `/batch` |
| **Automatic detection** | - | - | ✅ opt-in per group chat |
| **Inline mode** (use in any chat without adding the bot) | - | - | ✅ |
| **Works offline** | ✅ (PWA) | - | - |
| **Storage** | Browser local storage | SQLite | SQLite |

## Embed-domain fixes (shared logic)

| Platform | Fixed to |
|---|---|
| X / Twitter | `fixupx.com` (usernames replaced with `i`) |
| Instagram | `oginstagram.com` |
| TikTok | `tnktok.com` (`vm.` / `vt.` share links keep their subdomain) |
| YouTube Shorts | `koutube.com` (regular watch links stay on `youtube.com`) |
| Facebook | `facebed.com` |
| Reddit | `vxreddit.com` |
| Threads | `fixthreads.seria.moe` |
| Bluesky | `fxbsky.app` |
| Twitch | `fxtwitch.seria.moe` |
| Spotify | `fxspotify.com` |
| Pixiv | `phixiv.net` |
| Tumblr | `tpmblr.com` |
| BiliBili | `vxbilibili.com` |
| DeviantArt | `fixdeviantart.com` (art / journal pages) |
| Newgrounds | `fixnewgrounds.com` (art pages) |
| Fur Affinity | `xfuraffinity.net` (submission pages) |
| Mastodon | `fx.zillanlabs.tech/<instance>/@user/<id>` |
| Discord (canary/PTB) | normalized to `discord.com` |

Some fixers only serve certain page types, so those swaps are path-gated: a
DeviantArt gallery or Fur Affinity profile link stays on its original domain
rather than being pointed at a fixer that would 404. Mastodon isn't a plain
host swap either - it has no single hostname, so the ten instances FxMastodon
covers are enumerated and the instance is moved into the path.

`youtu.be` links are also normalized to `youtube.com` for consistency.

Trackers are also stripped from a much wider set of platforms (LinkedIn,
Amazon, Substack, GitHub, Pinterest, Snapchat, eBay, AliExpress, and more)
even where there's no embed-domain swap to apply. On every host - including
ones with no platform rules at all - any parameter starting with `utm_` is
removed, so UTM variants beyond the named list (`utm_creative`,
`utm_pubreferrer`, `utm_swu`, ...) are caught too. Matching is
case-insensitive, and the URL fragment (`#section-3`) is always preserved.

## Getting started

- **Web app**: live at [fixup.uwuapps.org](https://fixup.uwuapps.org); see
  [main-site/README.md](main-site/README.md) for details.
- **Discord bot**: [invite it to a server](https://discord.com/oauth2/authorize?client_id=1524465330091724880);
  see [discord-bot/README.md](discord-bot/README.md) for features and
  [discord-bot/SETUP.md](discord-bot/SETUP.md) to self-host it.
- **Telegram bot**: message [@uwuFix_bot](https://t.me/uwuFix_bot); see
  [telegram-bot/README.md](telegram-bot/README.md) for features and
  [telegram-bot/SETUP.md](telegram-bot/SETUP.md) to self-host it.

Both bots deploy the same way: a Python venv on a VPS, run inside `tmux`,
with SQLite for persistence - no external database or hosting service
required.
