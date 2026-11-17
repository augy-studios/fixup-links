// Report a bug: the form (the site's js/bug-report.js, the apps' lib/features/bug/) sends what
// went wrong here, and it reaches Augy as a message from a Telegram bot. As sgbus-timings' own,
// from which it's taken.
//
//   POST { text, contact?, version?, platform?, device?, page?, lang?, website?, images?, full? }
//     → 200 { id }
//
// `images` (optional) is up to MAX_IMAGES pictures as JPEG, PNG or WebP data URLs, each at most
// MAX_IMAGE_BYTES (js/bug-report.js makes them JPEGs of about 900 KB at most). `full` (optional)
// lists which of them are whole-page screenshots: as tall as the page, which Telegram shrinks as
// a photo till it can't be read, so each also goes as a file (sendDocument), at its full size.
//
// Each report gets an ID, reportId(): the day in Singapore and four letters, "20261103-7K3Q", in
// the message's heading and answered to the form, which shows it, so a report can be talked
// about by it. Nothing's stored: the day keeps them in order, the letters apart.
//
// It goes as a Telegram rich message (Bot API sendRichMessage): a heading, a table of what the
// form added, what was typed under its own heading, and the pictures in the message itself,
// uploaded with it (InputRichMessage `media`, each a tg://photo?id= link in the Markdown). If a
// chat won't take a rich message, it gets what it got before: the same words as plain text
// (sendMessage), then the pictures as a photo or an album replying to it.
//
// What's sent on is what the person typed (`text`, and `contact` if they gave one), with what
// the form adds and shows them first: the app's version, which app (web, Android, desktop), the
// device as their browser describes it, the page they were on and the
// language. Nothing else: not their address, location or anything from their favourites.
//
//   BUG_REPORT_BOT_TOKEN  the bot that sends it (BotFather's token; the Telegram bot's own will do)
//   BUG_REPORT_CHAT_ID    the chats it's sent to, one or more, split by commas, spaces or new
//                         lines: a chat ID (a person, who must have started the bot first; a
//                         group or channel the bot's in), a public group or channel's @name, or
//                         <chat ID>/<topic ID> for one topic of a group with topics.
//                         main-site/README.md's "Report a bug" says how to find each
//
// Sent to every chat at once; it counts as sent if one of them took it, and a chat that didn't
// is logged by its place in the list, with Telegram's reason.
//
// Without either it answers 503, and the form offers email instead. A public endpoint, so it's
// kept small: at most MAX_TEXT characters and MAX_BODY bytes in all, PER_MINUTE a minute and
// PER_HOUR an hour from one IP, and ALL_PER_HOUR from everyone together, counted in this
// function's instance (uwuFix keeps no database). Everything typed is escaped (escapeMd), so nothing
// in it is read as Telegram's Rich Markdown or HTML; the plain text fallback has no parse_mode. `website` is a field people never see: filled in, it's
// a bot, told it went and sent nothing.

// Counts kept in this instance: { key: [times] }. An instance lives minutes to hours, so these
// are a brake, not a wall.
const seen = new Map();
function countWithin(key, windowMs) {
  const now = Date.now();
  let times = seen.get(key);
  if (!times) {
    times = [];
  }
  const list = [];
  for (const time of times) {
    if (now - time < windowMs) {
      list.push(time);
    }
  }
  list.push(now);
  seen.set(key, list);
  if (seen.size > 5000) {
    seen.clear();
  }
  return list.length;
}
async function rateLimited(key, perMinute) {
  return countWithin(`m:${key}`, 60 * 1000) > perMinute;
}

const MAX_TEXT = 2000;
const MAX_CONTACT = 200;
const MAX_BODY = 8 * 1024;
const MAX_IMAGES = 3;
const MAX_IMAGE_BYTES = 1200 * 1024;
const IMAGE_RE = /^data:image\/(jpeg|png|webp);base64,([A-Za-z0-9+/=]+)$/;
const PER_MINUTE = 2;
const PER_HOUR = 6;
const ALL_PER_HOUR = 60;
const TELEGRAM_MS = 10 * 1000;
const PLATFORMS = { web: "Web", pwa: "Web, installed", android: "Android app", desktop: "Desktop app" };
// A report ID's letters: no 0 or O, 1, I or L, so one read out or typed back can't be mistaken.
const ID_LETTERS = "23456789ABCDEFGHJKMNPQRSTUVWXYZ";
const ID_LENGTH = 4;

function randomBytes(count) {
  return crypto.getRandomValues(new Uint8Array(count));
}

// "20261103-7K3Q": the day in Singapore it was sent, and ID_LENGTH random letters.
export function reportId(now = new Date(), random = randomBytes) {
  const day = new Date(now.getTime() + 8 * 3600 * 1000).toISOString().slice(0, 10).replace(/-/g, "");
  let letters = "";
  for (const byte of random(ID_LENGTH)) {
    letters += ID_LETTERS[byte % ID_LETTERS.length];
  }
  return `${day}-${letters}`;
}

// The whole-page screenshots among `count` pictures, as their indexes: `full` as sent, each
// once and in range, anything else left out.
export function fullShots(full, count) {
  if (!Array.isArray(full)) {
    return [];
  }
  const indexes = new Set();
  for (const index of full) {
    if (Number.isInteger(index) && index >= 0 && index < count) {
      indexes.add(index);
    }
  }
  return [...indexes].sort(function (first, second) {
    return first - second;
  });
}

// BUG_REPORT_CHAT_ID as [{ chat_id, message_thread_id? }], in order; anything that isn't a chat
// ID, an @name or a chat ID with a topic is left out.
export function chats(value = process.env.BUG_REPORT_CHAT_ID) {
  let text = "";
  if (value) {
    text = String(value);
  }
  const result = [];
  for (const entry of text.split(/[\s,]+/)) {
    const match = entry.match(/^(-?\d+)(?:\/(\d+))?$/);
    if (match) {
      if (match[2]) {
        result.push({ chat_id: match[1], message_thread_id: Number(match[2]) });
      } else {
        result.push({ chat_id: match[1] });
      }
    } else if (/^@[A-Za-z]\w{3,}$/.test(entry)) {
      result.push({ chat_id: entry });
    }
  }
  return result;
}

export function configured() {
  return Boolean(process.env.BUG_REPORT_BOT_TOKEN && chats().length);
}

// A string as given, trimmed and cut to `max`, with control characters other than new lines
// and tabs taken out. Anything that isn't a string is "".
function clean(value, max, { lines = false } = {}) {
  if (typeof value !== "string") {
    return "";
  }
  let controlCharacters = /[\u0000-\u001f\u007f]/g;
  if (lines) {
    controlCharacters = /[\u0000-\u0008\u000b-\u001f\u007f]/g;
  }
  const cleaned = value.replace(controlCharacters, "").trim();
  if (cleaned.length > max) {
    return cleaned.slice(0, max);
  }
  return cleaned;
}

// The value cleaned, or the fallback when nothing's left of it.
function cleanOr(value, max, fallback) {
  const cleaned = clean(value, max);
  if (cleaned) {
    return cleaned;
  }
  return fallback;
}

// The pictures sent, as [{ type, bytes }], or null if any isn't one (a bad data URL, too big,
// too many).
export function images(list) {
  if (list == null) {
    return [];
  }
  if (!Array.isArray(list) || list.length > MAX_IMAGES) {
    return null;
  }
  const result = [];
  for (const item of list) {
    let match = null;
    if (typeof item === "string") {
      match = IMAGE_RE.exec(item);
    }
    if (!match) {
      return null;
    }
    const bytes = Buffer.from(match[2], "base64");
    if (!bytes.length || bytes.length > MAX_IMAGE_BYTES) {
      return null;
    }
    result.push({ type: match[1], bytes });
  }
  return result;
}

// A picture's file extension: "jpg" for JPEG, otherwise its type ("png", "webp").
function extensionOf(picture) {
  if (picture.type === "jpeg") {
    return "jpg";
  }
  return picture.type;
}

// A picture's bytes as a file to upload.
function pictureBlob(picture) {
  return new Blob([picture.bytes], { type: `image/${picture.type}` });
}

// A Telegram form with the chat's fields (chat_id, message_thread_id) filled in, and, with
// `replyTo`, set to reply to that message.
function chatForm(chat, replyTo) {
  const form = new FormData();
  for (const [key, value] of Object.entries(chat)) {
    form.append(key, String(value));
  }
  if (replyTo) {
    form.append("reply_parameters", JSON.stringify({ message_id: replyTo, allow_sending_without_reply: true }));
  }
  return form;
}

// A reply's JSON, or null if it isn't JSON.
async function readJson(response) {
  try {
    return await response.json();
  } catch {
    return null;
  }
}

// The error for a reply Telegram refused, with its reason when it gave one.
async function telegramError(response) {
  const reply = await readJson(response);
  const reason = reply?.description;
  if (reason) {
    return new Error(`Telegram replied ${response.status}: ${reason}`);
  }
  return new Error(`Telegram replied ${response.status}`);
}

// The pictures to one chat, replying to the report (`replyTo`): one as a photo, more as an album.
async function sendImages(chat, pictures, replyTo, id) {
  const form = chatForm(chat, replyTo);
  let caption;
  if (pictures.length === 1) {
    caption = `Picture for report ${id}`;
  } else {
    caption = `${pictures.length} pictures for report ${id}`;
  }
  let method;
  if (pictures.length === 1) {
    method = "sendPhoto";
    form.append("photo", pictureBlob(pictures[0]), `picture.${extensionOf(pictures[0])}`);
    form.append("caption", caption);
  } else {
    method = "sendMediaGroup";
    const media = [];
    for (let index = 0; index < pictures.length; index++) {
      const picture = pictures[index];
      form.append(`p${index}`, pictureBlob(picture), `picture${index + 1}.${extensionOf(picture)}`);
      const entry = { type: "photo", media: `attach://p${index}` };
      // The album's caption goes on its first picture.
      if (index === 0) {
        entry.caption = caption;
      }
      media.push(entry);
    }
    form.append("media", JSON.stringify(media));
  }
  const response = await fetch(`https://api.telegram.org/bot${process.env.BUG_REPORT_BOT_TOKEN}/${method}`, { method: "POST", body: form, signal: AbortSignal.timeout(TELEGRAM_MS * 2) });
  if (!response.ok) {
    throw await telegramError(response);
  }
}

// A whole-page screenshot (`full`), as a file, so Telegram keeps it at its full size: replying to
// the report where it's known, captioned with the report's ID.
async function sendFile(chat, picture, pictureNumber, id, replyTo) {
  const form = chatForm(chat, replyTo);
  const extension = extensionOf(picture);
  form.append("document", pictureBlob(picture), `report-${id}-page-${pictureNumber}.${extension}`);
  form.append("caption", `Whole page, picture ${pictureNumber}, at full size: report ${id}`);
  form.append("disable_content_type_detection", "true");
  const response = await fetch(`https://api.telegram.org/bot${process.env.BUG_REPORT_BOT_TOKEN}/sendDocument`, { method: "POST", body: form, signal: AbortSignal.timeout(TELEGRAM_MS * 2) });
  if (!response.ok) {
    throw await telegramError(response);
  }
}

// What the form added, as [label, value], in order: the report's ID first.
function details(body) {
  let platform = PLATFORMS[body.platform];
  if (!platform) {
    platform = "Unknown";
  }
  const version = clean(body.version, 60);
  let app = platform;
  if (version) {
    app = `${platform} ${version}`;
  }
  const rows = [];
  if (body.id) {
    rows.push(["Report", body.id]);
  }
  rows.push(["App", app]);
  rows.push(["Device", cleanOr(body.device, 200, "not given")]);
  rows.push(["Page", cleanOr(body.page, 100, "not given")]);
  rows.push(["Language", cleanOr(body.lang, 10, "not given")]);
  rows.push(["Contact", cleanOr(body.contact, MAX_CONTACT, "none given")]);
  return rows;
}

// The message Augy gets as plain text, where a rich message won't go: what the form added,
// then what was typed.
export function message(body) {
  let heading = "Bug report, uwuFix";
  if (body.id) {
    heading = `Bug report ${body.id}, uwuFix`;
  }
  const lines = [heading, ""];
  for (const [label, value] of details(body)) {
    lines.push(`${label}: ${value}`);
  }
  if (Array.isArray(body.images) && body.images.length) {
    lines.push(`Pictures: ${body.images.length}, below`);
  }
  lines.push("");
  lines.push(clean(body.text, MAX_TEXT, { lines: true }));
  return lines.join("\n");
}

// Text for Telegram's Rich Markdown, read as it is: Markdown's and HTML's characters, and the
// ones its own syntax uses (== marked, || spoiler, $ formulas), each behind a backslash, and a
// line that would start a list or a heading made not to.
const MD_SPECIAL = /([\\*_~`|\[\]#>=<!$&^(){}])/g;
export function escapeMd(text) {
  return String(text)
    .replace(MD_SPECIAL, "\\$1")
    .replace(/^(\s*)([-+])(?=\s|$)/gm, "$1\\$2")
    .replace(/^(\s*\d+)([.)])/gm, "$1\\$2");
}
// A table cell: escaped, on one line.
function escapeCell(text) {
  return escapeMd(String(text).replace(/\s*\n\s*/g, " "));
}

/**
 * The rich message: a heading, the form's details as a table, what was typed under a heading of
 * its own (each line kept a line), then each picture as a block of its own, `p0`, `p1`... the
 * ids of the files uploaded with it.
 */
export function richMarkdown(body, pictures = 0) {
  const typed = [];
  for (const line of clean(body.text, MAX_TEXT, { lines: true }).split("\n")) {
    typed.push(escapeMd(line));
  }
  let heading = "# Bug report";
  if (body.id) {
    heading = `# Bug report ${escapeMd(body.id)}`;
  }
  const lines = [
    heading,
    "*uwuFix*",
    "",
    "| Detail | Given |",
    "| --- | --- |",
  ];
  for (const [label, value] of details(body)) {
    lines.push(`| ${label} | ${escapeCell(value)} |`);
  }
  lines.push("", "## What went wrong", "");
  // Two spaces at a line's end keep the next on a line of its own; a blank line stays one.
  for (let index = 0; index < typed.length; index++) {
    const line = typed[index];
    if (index < typed.length - 1 && line && typed[index + 1]) {
      lines.push(`${line}  `);
    } else {
      lines.push(line);
    }
  }
  if (pictures) {
    if (pictures === 1) {
      lines.push("", "## Picture");
    } else {
      lines.push("", `## Pictures (${pictures})`);
    }
    for (let index = 0; index < pictures; index++) {
      if (pictures > 1) {
        lines.push("", `![](tg://photo?id=p${index} "Picture ${index + 1} of ${pictures}")`);
      } else {
        lines.push("", `![](tg://photo?id=p${index})`);
      }
    }
  }
  return lines.join("\n");
}

// The report as a rich message to one chat, its pictures in it: a form, so the files go with it.
// Its message's ID, for the whole-page files to reply to, or null if Telegram didn't say.
async function sendRich(chat, body, pictures) {
  const form = chatForm(chat, null);
  const richMessage = { markdown: richMarkdown(body, pictures.length) };
  if (pictures.length) {
    const media = [];
    for (let index = 0; index < pictures.length; index++) {
      media.push({ id: `p${index}`, media: { type: "photo", media: `attach://p${index}` } });
    }
    richMessage.media = media;
  }
  form.append("rich_message", JSON.stringify(richMessage));
  for (let index = 0; index < pictures.length; index++) {
    const picture = pictures[index];
    form.append(`p${index}`, pictureBlob(picture), `picture${index + 1}.${extensionOf(picture)}`);
  }
  let timeoutMs = TELEGRAM_MS;
  if (pictures.length) {
    timeoutMs = TELEGRAM_MS * 2;
  }
  const response = await fetch(`https://api.telegram.org/bot${process.env.BUG_REPORT_BOT_TOKEN}/sendRichMessage`, {
    method: "POST", body: form, signal: AbortSignal.timeout(timeoutMs),
  });
  if (response.ok) {
    const reply = await readJson(response);
    const messageId = reply?.result?.message_id;
    if (messageId === null || messageId === undefined) {
      return null;
    }
    return messageId;
  }
  throw await telegramError(response);
}

// Over the hour's limit: one IP's, or everyone's.
async function overHour(ip) {
  if (countWithin(`h:${ip}`, 3600 * 1000) > PER_HOUR) {
    return true;
  }
  return countWithin("h:all", 3600 * 1000) > ALL_PER_HOUR;
}

// What to log for a failed send: "Telegram took too long" for a timeout, otherwise its message.
function describeFailure(error) {
  if (error.name === "TimeoutError") {
    return "Telegram took too long";
  }
  return error.message;
}

// The caller's IP, as Vercel passes it on, or "unknown".
function callerIp(request) {
  const realIp = request.headers["x-real-ip"];
  if (realIp) {
    return realIp;
  }
  let forwardedFor = request.headers["x-forwarded-for"];
  if (!forwardedFor) {
    forwardedFor = "";
  }
  const firstForwarded = String(forwardedFor).split(",")[0].trim();
  if (firstForwarded) {
    return firstForwarded;
  }
  return "unknown";
}

/**
 * The endpoint: checks the request (method, origin, size, text, pictures, rate limits, the
 * honeypot), then sends the report to every chat at once, as a rich message or as plain text
 * where that won't go, and answers with its ID if at least one chat took it.
 */
export default async function handler(request, response) {
  response.setHeader("Cache-Control", "no-store");
  if (request.method !== "POST") {
    response.setHeader("Allow", "POST");
    return response.status(405).json({ error: "method not allowed" });
  }
  if (!configured()) {
    return response.status(503).json({ error: "Bug reports can't be sent from the app yet." });
  }

  // Only from the site's own page: a browser sends Origin with a cross-site POST.
  const origin = request.headers.origin;
  if (origin) {
    let host = "";
    try {
      host = new URL(origin).host;
    } catch { /* not a URL: refused below */ }
    if (host !== request.headers.host) {
      return response.status(403).json({ error: "Not from this site." });
    }
  }

  let body = null;
  if (request.body && typeof request.body === "object") {
    body = request.body;
  }
  if (!body) {
    return response.status(400).json({ error: "Nothing was sent." });
  }
  const pictures = images(body.images);
  if (!pictures) {
    return response.status(400).json({ error: `Pictures must be images, at most ${MAX_IMAGES}, each under ${Math.round(MAX_IMAGE_BYTES / 1024 / 1024 * 10) / 10} MB.` });
  }
  if (JSON.stringify({ ...body, images: undefined }).length > MAX_BODY) {
    return response.status(413).json({ error: "That's too long to send." });
  }
  if (typeof body.text !== "string" || clean(body.text, MAX_TEXT + 1, { lines: true }).length < 5) {
    return response.status(400).json({ error: "Please say what went wrong." });
  }
  if (body.text.trim().length > MAX_TEXT) {
    return response.status(400).json({ error: `Please keep it under ${MAX_TEXT} characters.` });
  }

  const ip = callerIp(request);
  if (await rateLimited(`bug:${ip}`, PER_MINUTE)) {
    return response.status(429).json({ error: "That's a lot of reports at once. Try again in a minute." });
  }
  // The bot's field: no message, and no sign it was noticed.
  if (body.website) {
    return response.status(200).json({ id: reportId() });
  }
  if (await overHour(ip)) {
    return response.status(429).json({ error: "That's a lot of reports this hour. Try again later." });
  }

  // To every chat at once, as a rich message, or as before where that won't go. One that took
  // it is enough; the others are logged.
  const id = reportId();
  const report = { ...body, id };
  const full = fullShots(body.full, pictures.length);
  // Each whole-page screenshot as a file too, after the report; the report counts as sent even
  // if they don't go.
  async function sendFiles(chat, chatIndex, replyTo) {
    for (const pictureIndex of full) {
      try {
        await sendFile(chat, pictures[pictureIndex], pictureIndex + 1, id, replyTo);
      } catch (error) {
        console.error(`bug-report: chat ${chatIndex + 1}: whole page ${pictureIndex + 1}: ${error.message}`);
      }
    }
  }
  const text = message(report);

  // The report to one chat: true if it took it.
  async function sendToChat(chat, chatIndex) {
    try {
      const sent = await sendRich(chat, report, pictures);
      await sendFiles(chat, chatIndex, sent);
      return true;
    } catch (error) {
      console.error(`bug-report: chat ${chatIndex + 1}: rich message: ${describeFailure(error)}; sending it as plain text`);
    }
    try {
      const telegramResponse = await fetch(`https://api.telegram.org/bot${process.env.BUG_REPORT_BOT_TOKEN}/sendMessage`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ ...chat, text, link_preview_options: { is_disabled: true } }),
        signal: AbortSignal.timeout(TELEGRAM_MS),
      });
      if (telegramResponse.ok) {
        // Then its pictures, replying to it. The report counts as sent even if they don't go.
        const reply = await readJson(telegramResponse);
        const replyTo = reply?.result?.message_id;
        if (pictures.length) {
          try {
            await sendImages(chat, pictures, replyTo, id);
          } catch (error) {
            console.error(`bug-report: chat ${chatIndex + 1}: pictures: ${error.message}`);
          }
        }
        await sendFiles(chat, chatIndex, replyTo);
        return true;
      }
      // Telegram's reason, for the logs: never the token, which is only in the address.
      const refusal = await telegramError(telegramResponse);
      console.error(`bug-report: chat ${chatIndex + 1}: ${refusal.message}`);
    } catch (error) {
      console.error(`bug-report: chat ${chatIndex + 1}: ${describeFailure(error)}`);
    }
    return false;
  }

  const results = await Promise.all(chats().map(sendToChat));
  if (!results.includes(true)) {
    return response.status(502).json({ error: "Couldn't send it right now. Please try again." });
  }
  return response.status(200).json({ id });
}
