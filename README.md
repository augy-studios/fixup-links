# Link Fixer

Clean URLs, strip trackers, and swap in embed-friendly domains so link
previews actually render. This repo has three surfaces sharing the same
cleanup logic: a web app, a Discord bot, and a Telegram bot.

| | [🌐 Web App](main-site) | [💬 Discord Bot](discord-bot) | [✈️ Telegram Bot](telegram-bot) |
|---|---|---|---|
| **What it is** | Client-side PWA at [fixup.uwuapps.org](https://fixup.uwuapps.org) | Slash-command bot for Discord servers | Command + inline bot for Telegram |
| **Use it via** | Browser, or installed as an app | `/fix`, `/batch`, `/history`, `/help` | `/fix`, `/batch`, `/history`, `/settings`, `/donate`, `/help`, inline mode |
| **Tracker removal** | ✅ | ✅ | ✅ |
| **Embed-domain fixing** | ✅ | ✅ | ✅ |
| **Redirect following** | ✅ | ✅ | ✅ |
| **Google Search extraction** | ✅ | ✅ | ✅ |
| **History** | ✅ local, per-browser | ✅ per-user, paginated | ✅ per-user, paginated + inline picker |
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
| Instagram | `kkclip.com` |
| TikTok | `kktiktok.com` / `vt.kktiktok.com` |
| Facebook | `facebed.com` |
| Reddit | `vxreddit.com` |
| Bluesky | `bskx.app` |
| Discord (canary/PTB) | normalized to `discord.com` |

Trackers are also stripped from a much wider set of platforms (YouTube,
LinkedIn, Amazon, Substack, GitHub, Pinterest, Snapchat, Spotify, eBay,
AliExpress, and more) even where there's no embed-domain swap to apply.

## Getting started

- **Web app**: see [main-site/README.md](main-site/README.md).
- **Discord bot**: see [discord-bot/README.md](discord-bot/README.md) for
  features and [discord-bot/SETUP.md](discord-bot/SETUP.md) for deployment.
- **Telegram bot**: see [telegram-bot/README.md](telegram-bot/README.md) for
  features and [telegram-bot/SETUP.md](telegram-bot/SETUP.md) for
  deployment.

Both bots deploy the same way: a Python venv on a VPS, run inside `tmux`,
with SQLite for persistence - no external database or hosting service
required.
