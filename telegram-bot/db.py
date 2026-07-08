"""SQLite persistence layer.

Backs four things:
  * fix_results    - the outcome of a single /fix (or autodetect/inline) call.
                      Buttons on the resulting message (QR / toggle / refresh /
                      delete) only carry this row's integer id in their
                      callback_data, so they keep working forever - including
                      across bot restarts - as long as the row still exists,
                      exactly like the Discord bot's DynamicItem buttons.
  * batch_results  - same idea as fix_results but for a /batch call's
                      "Copy all" button.
  * history        - per-user log of links that have been fixed, for /history.
  * chat_settings  - per-chat preferences (currently just autodetect on/off).
"""
from __future__ import annotations

from pathlib import Path

import aiosqlite

SCHEMA = """
CREATE TABLE IF NOT EXISTS fix_results (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    chat_id INTEGER NOT NULL,
    requester_id INTEGER NOT NULL,
    original_url TEXT NOT NULL,
    cleaned_url TEXT NOT NULL,
    platform TEXT,
    showing_original INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS batch_results (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    chat_id INTEGER NOT NULL,
    requester_id INTEGER NOT NULL,
    cleaned_urls TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    original_url TEXT NOT NULL,
    cleaned_url TEXT NOT NULL,
    platform TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_history_user ON history(user_id, id DESC);

CREATE TABLE IF NOT EXISTS chat_settings (
    chat_id INTEGER PRIMARY KEY,
    autodetect_enabled INTEGER NOT NULL DEFAULT 1
);
"""


async def init_db(path: str) -> aiosqlite.Connection:
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    conn = await aiosqlite.connect(path)
    conn.row_factory = aiosqlite.Row
    await conn.executescript(SCHEMA)
    await conn.commit()
    return conn


async def add_fix_result(db, *, chat_id, requester_id, original_url, cleaned_url, platform) -> int:
    cur = await db.execute(
        "INSERT INTO fix_results (chat_id, requester_id, original_url, cleaned_url, platform) "
        "VALUES (?, ?, ?, ?, ?)",
        (chat_id, requester_id, original_url, cleaned_url, platform),
    )
    await db.commit()
    return cur.lastrowid


async def get_fix_result(db, fix_id: int):
    cur = await db.execute("SELECT * FROM fix_results WHERE id = ?", (fix_id,))
    return await cur.fetchone()


async def update_fix_result(db, fix_id: int, *, cleaned_url=None, platform=None, showing_original=None):
    row = await get_fix_result(db, fix_id)
    if not row:
        return
    cleaned_url = row['cleaned_url'] if cleaned_url is None else cleaned_url
    platform = row['platform'] if platform is None else platform
    showing_original = row['showing_original'] if showing_original is None else int(showing_original)
    await db.execute(
        "UPDATE fix_results SET cleaned_url = ?, platform = ?, showing_original = ? WHERE id = ?",
        (cleaned_url, platform, showing_original, fix_id),
    )
    await db.commit()


async def add_batch_result(db, *, chat_id, requester_id, cleaned_urls: list[str]) -> int:
    cur = await db.execute(
        "INSERT INTO batch_results (chat_id, requester_id, cleaned_urls) VALUES (?, ?, ?)",
        (chat_id, requester_id, '\n'.join(cleaned_urls)),
    )
    await db.commit()
    return cur.lastrowid


async def get_batch_result(db, batch_id: int):
    cur = await db.execute("SELECT * FROM batch_results WHERE id = ?", (batch_id,))
    return await cur.fetchone()


async def add_history(db, *, user_id, original_url, cleaned_url, platform):
    await db.execute(
        "INSERT INTO history (user_id, original_url, cleaned_url, platform) VALUES (?, ?, ?, ?)",
        (user_id, original_url, cleaned_url, platform),
    )
    await db.commit()


async def get_history_page(db, user_id: int, offset: int, limit: int):
    cur = await db.execute(
        "SELECT * FROM history WHERE user_id = ? ORDER BY id DESC LIMIT ? OFFSET ?",
        (user_id, limit + 1, offset),
    )
    rows = await cur.fetchall()
    has_more = len(rows) > limit
    return rows[:limit], has_more


async def touch_chat(db, chat_id: int, *, default_autodetect: bool):
    """Registers a chat the bot has seen, without clobbering an existing preference."""
    await db.execute(
        "INSERT INTO chat_settings (chat_id, autodetect_enabled) VALUES (?, ?) "
        "ON CONFLICT(chat_id) DO NOTHING",
        (chat_id, int(default_autodetect)),
    )
    await db.commit()


async def get_autodetect_enabled(db, chat_id: int, *, default_autodetect: bool) -> bool:
    cur = await db.execute("SELECT autodetect_enabled FROM chat_settings WHERE chat_id = ?", (chat_id,))
    row = await cur.fetchone()
    if row is None:
        return default_autodetect
    return bool(row['autodetect_enabled'])


async def set_autodetect_enabled(db, chat_id: int, enabled: bool):
    await db.execute(
        "INSERT INTO chat_settings (chat_id, autodetect_enabled) VALUES (?, ?) "
        "ON CONFLICT(chat_id) DO UPDATE SET autodetect_enabled = excluded.autodetect_enabled",
        (chat_id, int(enabled)),
    )
    await db.commit()


async def count_known_chats(db) -> int:
    cur = await db.execute("SELECT COUNT(*) AS n FROM chat_settings")
    row = await cur.fetchone()
    return row['n'] if row else 0
