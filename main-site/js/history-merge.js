/* Merging two histories, for sharing history between devices (js/sync.js). The same rules as the
   apps' (flutter/lib/data/history.dart), held to each other by flutter/test/history_test.dart:

   - Each entry from another device is checked first (sanitize): anything that isn't a link
     cleaned to http(s), with a date, is dropped, and every field is cut to size. It's input from
     another device, so nothing in it is trusted.
   - One entry per cleaned link: the newer one stays, its title filled from the other's if it had
     none.
   - Newest first, at most 100 (MAX_HISTORY in script.js), and no two with the same id.

     HistoryMerge.sanitize(entry)          a clean copy, or null
     HistoryMerge.merge(mine, theirs)      { items, added }: added counts links new to mine */
'use strict';

(function () {
  const MAX = 100;
  const WEB = /^https?:\/\//i;

  const cut = (s, n) => (s.length > n ? s.slice(0, n) : s);

  function sanitize(v) {
    if (!v || typeof v !== 'object' || Array.isArray(v)) return null;
    const { cleaned, date, original, platform, title, id } = v;
    if (typeof cleaned !== 'string' || cleaned.length > 2048 || !WEB.test(cleaned)) return null;
    if (typeof date !== 'string' || date.length > 40) return null;
    const when = Date.parse(date);
    if (!Number.isFinite(when)) return null;
    return {
      id: typeof id === 'number' && Number.isInteger(id) ? id : when,
      original: typeof original === 'string' && original ? cut(original, 4096) : cleaned,
      cleaned,
      platform: typeof platform === 'string' && platform ? cut(platform, 60) : 'General',
      title: typeof title === 'string' && title ? cut(title, 300) : null,
      date: new Date(when).toISOString(),
    };
  }

  const time = (e) => Date.parse(e.date) || 0;

  function merge(mine, theirs) {
    const byLink = new Map();
    for (const e of mine) if (!byLink.has(e.cleaned)) byLink.set(e.cleaned, e);
    const known = new Set(byLink.keys());
    for (const raw of Array.isArray(theirs) ? theirs : []) {
      const e = sanitize(raw);
      if (!e) continue;
      const had = byLink.get(e.cleaned);
      if (!had) {
        byLink.set(e.cleaned, e);
      } else if (time(e) > time(had)) {
        byLink.set(e.cleaned, !e.title && had.title ? { ...e, title: had.title } : e);
      } else if (!had.title && e.title) {
        byLink.set(e.cleaned, { ...had, title: e.title });
      }
    }
    const kept = [...byLink.values()].sort((a, b) => time(b) - time(a) || b.id - a.id).slice(0, MAX);
    const ids = new Set();
    const items = kept.map((e) => {
      let id = e.id;
      while (ids.has(id)) id++;
      ids.add(id);
      return id === e.id ? e : { ...e, id };
    });
    return { items, added: items.filter((e) => !known.has(e.cleaned)).length };
  }

  window.HistoryMerge = { sanitize, merge, MAX };
})();
