# Setting up Report a bug (the Telegram bot)

**Report a bug** is in the site's Edge Tray, the Android app's Edge Tray, and the desktop apps'
rail, command bar (Ctrl+K) and Help menu. It's SG Bus Timings' own form: what went wrong (up to
2,000 characters), an optional way to reach the person, up to three pictures, and what helps find
the bug (the app and its version, the device, the page on show and the language), all shown before
it's sent.

`POST /api/bug-report` (`main-site/api/bug-report.js`) sends it to you on Telegram from a bot, as a
rich message: a heading with the report's ID, a table of what the form added, what was typed, and
its pictures inside it. A chat that won't take a rich message gets plain text with the pictures
replying to it.

- **Report ID:** each report gets one, the day in Singapore and four letters, e.g.
  `20261114-K7QM`. It's in the message's heading, and the form tells the person it, to quote if they
  write to you about it.
- **Screenshot a page:** on the site, **Screenshot this page** draws the whole page under the form,
  top to bottom. In the apps, **Screenshot a page** puts the form away so you can go to the page
  you want, then **Screenshot this page** takes it whole, scrolling a screen at a time, and brings
  the form back. A whole page also comes as a file, at its full size, as Telegram shrinks photos.

Until it's set up, the form works but says "Bug reports can't be sent from the app yet." and offers
an email to augy@augystudios.com instead.

## 1. Make the bot

1. In Telegram, open **@BotFather** and send `/newbot`.
2. Name it (e.g. `uwuFix bug reports`) and give it a username ending in `bot`.
3. BotFather answers with its token, like `123456789:AAH...`. That's `BUG_REPORT_BOT_TOKEN`.

> [!WARNING]
> The token is a password: anyone with it can send as the bot. Paste it only into Vercel and your
> own browser's address bar (step 2). If it leaks, send `/revoke` to BotFather and use the new one.

Use a bot just for reports, not @uwuFix_bot: a bot that's running somewhere takes its own updates,
so step 2 would show nothing. A reports-only bot runs nowhere.

## 2. Find the chat it sends to

Do the step for the kind of chat, then open
`https://api.telegram.org/bot<token>/getUpdates` in your browser and find `"chat":{"id": …}` in the
newest update (it lists the last day's).

| Chat | Do this | Its ID |
|---|---|---|
| **You, in a private chat** | Open the bot and press **Start** | A positive number, e.g. `424242` |
| **A group** | Add the bot, then send `/start@<botname>` in it | Negative, e.g. `-4012345678`; a supergroup's starts `-100` |
| **A topic in a group** | Send `/start@<botname>` in the topic and read `message_thread_id` | The group's `-100…` ID, `/`, the topic's: `-1001234567890/17` |
| **A channel** | Add the bot as an admin with **Post messages**, then post in it | In `channel_post`, starting `-100` (or `@channelname` if public) |

A group that becomes a supergroup gets a new `-100…` ID, and the old one fails with "group chat was
upgraded to a supergroup chat": find it again.

## 3. Give them to Vercel

Open the Vercel project for fixup.uwuapps.org, **Settings** > **Environment Variables**, and add,
with **Production** ticked and marked **Sensitive**:

| Key | Value |
|---|---|
| `BUG_REPORT_BOT_TOKEN` | The token from step 1 |
| `BUG_REPORT_CHAT_ID` | The chat's ID from step 2. Several, split by commas, each get it: `424242,-1001234567890/17` |

Then redeploy (**Deployments** > newest > **⋯** > **Redeploy**) so the function sees them.

## 4. Check it works

Open <https://fixup.uwuapps.org>, then **Report a bug** in the Edge Tray, type something, take a
screenshot, and send. The form should say "Sent as report 2026…-…. Thank you!", and the chat get it
with the same ID. With several chats, check each did: it counts as sent if one took it, and one
that didn't is in Vercel's log as `bug-report: chat 2: …` with Telegram's reason.

## Limits

To keep it from being used to spam you: 2 reports a minute and 6 an hour from one address, and 60
an hour in all, counted by each running copy of the function (there's no database). A hidden field
that only bots fill in is answered as if sent, and dropped. Pictures are JPEGs of at most about
900 KB each, made on the device.

## If something goes wrong

| What happens | What to do |
|---|---|
| "Bug reports can't be sent from the app yet." | The variables aren't set, or Vercel wasn't redeployed after (step 3) |
| "Couldn't send it right now." and nothing in the chat | Vercel's log for `/api/bug-report` says Telegram's reason: usually a wrong chat ID, or the person hasn't pressed **Start** in the bot |
| `chat not found` | The ID is wrong, or the bot isn't in that group or channel |
| `bot was blocked by the user` | You stopped the bot in your private chat: open it and press **Start** again |
| `not enough rights to send photos` | In a channel or group, give the bot the right to post media |
