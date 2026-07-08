"""SQLite persistence layer.

Backs three things:
  * pending_links  - links auto-detected in chat, keyed by id so the
                      "Fix Link" button attached to that message can look the
                      original URL back up after a bot restart.
  * fix_results    - the outcome of a single /fix (or auto-detect click),
                      keyed by id so Copy/QR buttons don't need to re-encode
                      a full URL into a 100-char custom_id.
  * batch_results  - same idea as fix_results but for a /batch call's
                      "Copy All" button.
  * history        - per-user log of links that have been fixed, for /history.
"""
from __future__ import annotations

from pathlib import Path

import aiosqlite

SCHEMA = """
CREATE TABLE IF NOT EXISTS pending_links (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    guild_id INTEGER,
    channel_id INTEGER NOT NULL,
    message_id INTEGER NOT NULL,
    author_id INTEGER NOT NULL,
    original_url TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS fix_results (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    original_url TEXT NOT NULL,
    cleaned_url TEXT NOT NULL,
    platform TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS batch_results (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
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
"""


async def init_db(path: str) -> aiosqlite.Connection:
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    conn = await aiosqlite.connect(path)
    conn.row_factory = aiosqlite.Row
    await conn.executescript(SCHEMA)
    await conn.commit()
    return conn


async def add_pending_link(db, *, guild_id, channel_id, message_id, author_id, original_url) -> int:
    cur = await db.execute(
        "INSERT INTO pending_links (guild_id, channel_id, message_id, author_id, original_url) "
        "VALUES (?, ?, ?, ?, ?)",
        (guild_id, channel_id, message_id, author_id, original_url),
    )
    await db.commit()
    return cur.lastrowid


async def get_pending_link(db, pending_id: int):
    cur = await db.execute("SELECT * FROM pending_links WHERE id = ?", (pending_id,))
    return await cur.fetchone()


async def add_fix_result(db, *, original_url, cleaned_url, platform) -> int:
    cur = await db.execute(
        "INSERT INTO fix_results (original_url, cleaned_url, platform) VALUES (?, ?, ?)",
        (original_url, cleaned_url, platform),
    )
    await db.commit()
    return cur.lastrowid


async def get_fix_result(db, fix_id: int):
    cur = await db.execute("SELECT * FROM fix_results WHERE id = ?", (fix_id,))
    return await cur.fetchone()


async def add_batch_result(db, *, user_id, cleaned_urls: list[str]) -> int:
    cur = await db.execute(
        "INSERT INTO batch_results (user_id, cleaned_urls) VALUES (?, ?)",
        (user_id, '\n'.join(cleaned_urls)),
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
