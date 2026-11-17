/* Merging two histories, for sharing history between devices (js/sync.js). The same rules as the
   apps' (flutter/lib/data/history.dart), held to each other by flutter/test/history_test.dart:

   - Each entry from another device is checked first (sanitize): anything that isn't a link
     cleaned to http(s), with a date, is dropped, and every field is cut to size. It's input from
     another device, so nothing in it is trusted.
   - One entry per cleaned link: the newer one stays, its title filled from the other's if it had
     none.
   - Newest first, at most 100 (MAXIMUM_HISTORY_ENTRIES in script.js), and no two with the same id.

     HistoryMerge.sanitize(entry)          a clean copy, or null
     HistoryMerge.merge(mine, theirs)      { items, added }: added counts links new to mine */
'use strict';

(function () {
  const MAXIMUM_ENTRIES = 100;
  const WEB_LINK_PATTERN = /^https?:\/\//i;

  // The text, cut to at most maximumLength characters.
  function truncate(text, maximumLength) {
    if (text.length > maximumLength) {
      return text.slice(0, maximumLength);
    }
    return text;
  }

  /**
   * A clean copy of one history entry from another device, or null when it isn't usable:
   * the cleaned link must be http(s) and the date must parse. Missing fields are filled in
   * (id from the date, original from the cleaned link, platform "General") and long ones cut.
   */
  function sanitize(value) {
    if (!value || typeof value !== 'object' || Array.isArray(value)) {
      return null;
    }
    const { cleaned, date, original, platform, title, id } = value;
    if (typeof cleaned !== 'string' || cleaned.length > 2048 || !WEB_LINK_PATTERN.test(cleaned)) {
      return null;
    }
    if (typeof date !== 'string' || date.length > 40) {
      return null;
    }
    const timestamp = Date.parse(date);
    if (!Number.isFinite(timestamp)) {
      return null;
    }

    let cleanId = timestamp;
    if (typeof id === 'number' && Number.isInteger(id)) {
      cleanId = id;
    }
    let cleanOriginal = cleaned;
    if (typeof original === 'string' && original) {
      cleanOriginal = truncate(original, 4096);
    }
    let cleanPlatform = 'General';
    if (typeof platform === 'string' && platform) {
      cleanPlatform = truncate(platform, 60);
    }
    let cleanTitle = null;
    if (typeof title === 'string' && title) {
      cleanTitle = truncate(title, 300);
    }
    return {
      id: cleanId,
      original: cleanOriginal,
      cleaned,
      platform: cleanPlatform,
      title: cleanTitle,
      date: new Date(timestamp).toISOString(),
    };
  }

  // An entry's date as a number for comparing, 0 when it doesn't parse.
  function entryTime(entry) {
    const time = Date.parse(entry.date);
    if (!time) {
      return 0;
    }
    return time;
  }

  /**
   * Merges another device's history (theirs) into this one (mine), by the rules at the top of
   * this file. Returns { items, added }, where added counts the links that mine didn't have.
   */
  function merge(mine, theirs) {
    const byLink = new Map();
    for (const entry of mine) {
      if (!byLink.has(entry.cleaned)) {
        byLink.set(entry.cleaned, entry);
      }
    }
    const known = new Set(byLink.keys());

    let theirEntries = [];
    if (Array.isArray(theirs)) {
      theirEntries = theirs;
    }
    for (const raw of theirEntries) {
      const entry = sanitize(raw);
      if (!entry) {
        continue;
      }
      const existing = byLink.get(entry.cleaned);
      if (!existing) {
        byLink.set(entry.cleaned, entry);
      } else if (entryTime(entry) > entryTime(existing)) {
        if (!entry.title && existing.title) {
          byLink.set(entry.cleaned, { ...entry, title: existing.title });
        } else {
          byLink.set(entry.cleaned, entry);
        }
      } else if (!existing.title && entry.title) {
        byLink.set(entry.cleaned, { ...existing, title: entry.title });
      }
    }

    // Newest first; for the same date, the higher id first.
    const sorted = [...byLink.values()].sort(function (first, second) {
      const timeDifference = entryTime(second) - entryTime(first);
      if (timeDifference) {
        return timeDifference;
      }
      return second.id - first.id;
    });
    const kept = sorted.slice(0, MAXIMUM_ENTRIES);

    // No two entries with the same id: a repeated id is moved up to the next free one.
    const ids = new Set();
    const items = [];
    for (const entry of kept) {
      let id = entry.id;
      while (ids.has(id)) {
        id++;
      }
      ids.add(id);
      if (id === entry.id) {
        items.push(entry);
      } else {
        items.push({ ...entry, id });
      }
    }

    let added = 0;
    for (const entry of items) {
      if (!known.has(entry.cleaned)) {
        added++;
      }
    }
    return { items, added };
  }

  window.HistoryMerge = { sanitize, merge, MAX: MAXIMUM_ENTRIES };
})();
