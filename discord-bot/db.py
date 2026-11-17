"""SQLite persistence layer.

Backs three things:
  * fix_results    - the outcome of a single /fix call, keyed by id so
                      the Details / Just the Link / QR buttons don't need
                      to re-encode a full URL into a 100-char custom_id.
                      Also carries the page title and change list so the
                      details embed can be rebuilt without re-fetching.
  * batch_results  - same idea as fix_results but for a /batch call's
                      "Copy All" button.
  * history        - per-user log of links that have been fixed, for /history.
"""
from __future__ import annotations

from pathlib import Path

import aiosqlite

SCHEMA = """
CREATE TABLE IF NOT EXISTS fix_results (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    original_url TEXT NOT NULL,
    cleaned_url TEXT NOT NULL,
    platform TEXT,
    title TEXT,
    changes TEXT,
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
    connection = await aiosqlite.connect(path)
    connection.row_factory = aiosqlite.Row
    await connection.executescript(SCHEMA)
    await _migrate(connection)
    await connection.commit()
    return connection


async def _migrate(connection: aiosqlite.Connection):
    """Adds columns introduced after the table was first created.

    CREATE TABLE IF NOT EXISTS is a no-op on an existing database, so
    databases created before these columns existed need them bolted on.
    """
    cursor = await connection.execute("PRAGMA table_info(fix_results)")
    existing_columns = set()
    for row in await cursor.fetchall():
        existing_columns.add(row['name'])
    for column in ('title', 'changes'):
        if column not in existing_columns:
            await connection.execute(f"ALTER TABLE fix_results ADD COLUMN {column} TEXT")


async def add_fix_result(db, *, original_url, cleaned_url, platform, title=None, changes=None) -> int:
    cursor = await db.execute(
        "INSERT INTO fix_results (original_url, cleaned_url, platform, title, changes) VALUES (?, ?, ?, ?, ?)",
        (original_url, cleaned_url, platform, title, changes),
    )
    await db.commit()
    return cursor.lastrowid


async def get_fix_result(db, fix_id: int):
    cursor = await db.execute("SELECT * FROM fix_results WHERE id = ?", (fix_id,))
    return await cursor.fetchone()


async def add_batch_result(db, *, user_id, cleaned_urls: list[str]) -> int:
    cursor = await db.execute(
        "INSERT INTO batch_results (user_id, cleaned_urls) VALUES (?, ?)",
        (user_id, '\n'.join(cleaned_urls)),
    )
    await db.commit()
    return cursor.lastrowid


async def get_batch_result(db, batch_id: int):
    cursor = await db.execute("SELECT * FROM batch_results WHERE id = ?", (batch_id,))
    return await cursor.fetchone()


async def add_history(db, *, user_id, original_url, cleaned_url, platform):
    await db.execute(
        "INSERT INTO history (user_id, original_url, cleaned_url, platform) VALUES (?, ?, ?, ?)",
        (user_id, original_url, cleaned_url, platform),
    )
    await db.commit()


async def get_history_page(db, user_id: int, offset: int, limit: int):
    cursor = await db.execute(
        "SELECT * FROM history WHERE user_id = ? ORDER BY id DESC LIMIT ? OFFSET ?",
        (user_id, limit + 1, offset),
    )
    rows = await cursor.fetchall()
    has_more = len(rows) > limit
    return rows[:limit], has_more
