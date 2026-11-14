// The Android app's releases (flutter/) on GitHub, tagged android-v<version> with the APK attached
// (release/README.md). Shared by api/app-release.js, which the app's updater reads, and
// api/push/release.js, which tells phones a new one is out. Vercel doesn't serve files starting
// with _ as functions.

// A page of them at a time, 100 being GitHub's most; PAGES pages at most, should it never stop.
const RELEASES = 'https://api.github.com/repos/augy-studios/fixup-links/releases?per_page=100&page=';
const PAGES = 10;
export const TAG = /^android-v(\d+(?:\.\d+)*)$/;

// Whether version a comes after version b, number by number: 1.10.0 after 1.9.0. The same as
// newer() in the app (flutter/lib/features/update/) and UpdateActivity.java.
export function newer(a, b) {
  const x = String(a).split('.').map(Number);
  const y = String(b).split('.').map(Number);
  for (let i = 0; i < Math.max(x.length, y.length); i++) {
    const d = (x[i] || 0) - (y[i] || 0);
    if (d) return d > 0;
  }
  return false;
}

// A release as the app wants it, or null if it isn't one to offer: a draft, a pre-release, a tag
// that isn't android-v*, or one published before its APK finished uploading.
//
//   { version: "1.2.0", apk: "https://github.com/.../uwufix-1.2.0.apk", size: 712345,
//     sha256: "ab12…" (GitHub's checksum of the file, or null), page: the release's page,
//     date: when it was published, summary and notes: what's new in it (notesOf) }
export function asRelease(rel) {
  const version = TAG.exec(rel?.tag_name || '')?.[1];
  if (!version || rel.draft || rel.prerelease) return null;
  const assets = rel.assets || [];
  const apk = assets.find((a) => a.name === `uwufix-${version}.apk`) || assets.find((a) => /\.apk$/i.test(a.name));
  if (!apk || apk.state !== 'uploaded') return null;
  return {
    version,
    apk: apk.browser_download_url,
    size: apk.size,
    sha256: /^sha256:[0-9a-f]{64}$/i.test(apk.digest || '') ? apk.digest.slice(7).toLowerCase() : null,
    page: rel.html_url,
    date: rel.published_at || null,
    ...notesOf(rel.body),
  };
}

// What's new in a release, for the app's changelog (UpdateActivity.java), from its notes as
// announcements/release-notes-<version>.md has them written: the first paragraph as `summary`,
// and under "## What's new" each "###" heading as a group of its items, "- **Title**: text" as
// { title, text }. Plain text, the Markdown taken out.
const plain = (s) => String(s)
  .replace(/\*\*(.+?)\*\*/g, '$1')
  .replace(/`([^`]+)`/g, '$1')
  .replace(/\[([^\]]+)\]\([^)]*\)/g, '$1')
  .replace(/(^|[\s(])_([^_]+)_(?=[\s).,:;]|$)/g, '$1$2')
  .replace(/\s+/g, ' ')
  .trim();

export function notesOf(body) {
  const text = String(body || '').replace(/\r\n/g, '\n');
  const first = text.trim().split(/\n\s*\n/)[0] || '';
  const summary = first.startsWith('#') || first.startsWith('|') ? '' : plain(first);
  const notes = [];
  const at = text.search(/^##\s+What.s new\s*$/im);
  if (at !== -1) {
    let group = null;
    for (const line of text.slice(at).split('\n').slice(1)) {
      if (/^##\s/.test(line)) break;
      const head = line.match(/^###\s+(.+)/);
      if (head) {
        group = { title: plain(head[1]), items: [] };
        notes.push(group);
        continue;
      }
      const item = line.match(/^[-*]\s+(.+)/);
      if (item) {
        if (!group) notes.push((group = { title: "What's new", items: [] }));
        const titled = item[1].match(/^\*\*(.+?)\*\*\s*[:.]?\s*(.*)$/);
        group.items.push(titled ? { title: plain(titled[1]).replace(/[:.]$/, ''), text: plain(titled[2]) } : { title: '', text: plain(item[1]) });
      } else if (group?.items.length && /^\s+\S/.test(line)) {
        // A line carried on, or a point under the item: part of the item.
        const last = group.items[group.items.length - 1];
        last.text = `${last.text} ${plain(line.replace(/^\s*[-*]\s+/, ''))}`.trim();
      }
    }
  }
  return { summary, notes: notes.filter((g) => g.items.length) };
}

// Every release to offer, newest first, from every page of them. GitHub allows 60 requests an
// hour per IP without a token; GITHUB_TOKEN (any token, no scopes needed for a public repository)
// raises that to 5,000, and is optional.
export async function allReleases() {
  const headers = { accept: 'application/vnd.github+json', 'x-github-api-version': '2022-11-28', 'user-agent': 'fixup-links' };
  if (process.env.GITHUB_TOKEN) headers.authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
  const releases = [];
  for (let page = 1; page <= PAGES; page++) {
    const r = await fetch(RELEASES + page, { headers, signal: AbortSignal.timeout(10_000) });
    if (!r.ok) throw new Error(`GitHub replied ${r.status}`);
    const list = await r.json();
    if (!Array.isArray(list)) break;
    releases.push(...list);
    // The last page: GitHub names no next one.
    if (!/rel="next"/.test(r.headers.get('link') || '')) break;
  }
  return releases.map(asRelease).filter(Boolean)
    .sort((a, b) => (newer(a.version, b.version) ? -1 : newer(b.version, a.version) ? 1 : 0));
}

// The newest release to offer, or null while there's none.
export async function latestRelease() {
  return (await allReleases())[0] || null;
}
