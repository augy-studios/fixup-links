// The Android app's releases (flutter/) on GitHub, tagged android-v<version> with the APK attached
// (release/README.md). Shared by api/app-release.js, which the app's updater reads, and
// api/push/release.js, which tells phones a new one is out. Vercel doesn't serve files starting
// with _ as functions.

// A page of them at a time, 100 being GitHub's most; PAGES pages at most, should it never stop.
const RELEASES = 'https://api.github.com/repos/augy-studios/fixup-links/releases?per_page=100&page=';
const PAGES = 10;
export const TAG = /^android-v(\d+(?:\.\d+)*)$/;

// Whether version `candidate` comes after version `current`, number by number: 1.10.0 after 1.9.0.
// The same as newer() in the app (flutter/lib/features/update/) and UpdateActivity.java.
export function newer(candidate, current) {
  const candidateParts = String(candidate).split('.').map(Number);
  const currentParts = String(current).split('.').map(Number);
  for (let index = 0; index < Math.max(candidateParts.length, currentParts.length); index++) {
    const difference = numberAt(candidateParts, index) - numberAt(currentParts, index);
    if (difference) {
      return difference > 0;
    }
  }
  return false;
}

// The number at this position of a version, or 0 past its end (or where it isn't a number).
function numberAt(numbers, index) {
  if (numbers[index]) {
    return numbers[index];
  }
  return 0;
}

// A release as the app wants it, or null if it isn't one to offer: a draft, a pre-release, a tag
// that isn't android-v*, or one published before its APK finished uploading.
//
//   { version: "1.2.0", apk: "https://github.com/.../uwufix-1.2.0.apk", size: 712345,
//     sha256: "ab12…" (GitHub's checksum of the file, or null), page: the release's page,
//     date: when it was published, summary and notes: what's new in it (notesOf) }
export function asRelease(release) {
  let tagName = release?.tag_name;
  if (!tagName) {
    tagName = '';
  }
  const version = TAG.exec(tagName)?.[1];
  if (!version || release.draft || release.prerelease) {
    return null;
  }
  let assets = release.assets;
  if (!assets) {
    assets = [];
  }
  // The APK named for this version, or else any APK.
  let apk = assets.find(function (asset) {
    return asset.name === `uwufix-${version}.apk`;
  });
  if (!apk) {
    apk = assets.find(function (asset) {
      return /\.apk$/i.test(asset.name);
    });
  }
  if (!apk || apk.state !== 'uploaded') {
    return null;
  }
  let digest = apk.digest;
  if (!digest) {
    digest = '';
  }
  let sha256 = null;
  if (/^sha256:[0-9a-f]{64}$/i.test(digest)) {
    sha256 = apk.digest.slice(7).toLowerCase();
  }
  let date = null;
  if (release.published_at) {
    date = release.published_at;
  }
  return {
    version,
    apk: apk.browser_download_url,
    size: apk.size,
    sha256,
    page: release.html_url,
    date,
    ...notesOf(release.body),
  };
}

// What's new in a release, for the app's changelog (UpdateActivity.java), from its notes as
// announcements/release-notes-<version>.md has them written: the first paragraph as `summary`,
// and under "## What's new" each "###" heading as a group of its items, "- **Title**: text" as
// { title, text }. Plain text, the Markdown taken out.
function plain(markdown) {
  return String(markdown)
    .replace(/\*\*(.+?)\*\*/g, '$1')
    .replace(/`([^`]+)`/g, '$1')
    .replace(/\[([^\]]+)\]\([^)]*\)/g, '$1')
    .replace(/(^|[\s(])_([^_]+)_(?=[\s).,:;]|$)/g, '$1$2')
    .replace(/\s+/g, ' ')
    .trim();
}

/**
 * Splits a release's Markdown notes into { summary, notes }: the first paragraph as the summary
 * (unless it's a heading or a table), and the "## What's new" section as groups of items.
 */
export function notesOf(body) {
  let bodyText = '';
  if (body) {
    bodyText = String(body);
  }
  const text = bodyText.replace(/\r\n/g, '\n');
  let first = text.trim().split(/\n\s*\n/)[0];
  if (!first) {
    first = '';
  }
  let summary = '';
  if (!first.startsWith('#') && !first.startsWith('|')) {
    summary = plain(first);
  }
  const notes = [];
  const at = text.search(/^##\s+What.s new\s*$/im);
  if (at !== -1) {
    let group = null;
    for (const line of text.slice(at).split('\n').slice(1)) {
      if (/^##\s/.test(line)) {
        break;
      }
      const heading = line.match(/^###\s+(.+)/);
      if (heading) {
        group = { title: plain(heading[1]), items: [] };
        notes.push(group);
        continue;
      }
      const item = line.match(/^[-*]\s+(.+)/);
      if (item) {
        if (!group) {
          group = { title: "What's new", items: [] };
          notes.push(group);
        }
        const titled = item[1].match(/^\*\*(.+?)\*\*\s*[:.]?\s*(.*)$/);
        if (titled) {
          group.items.push({ title: plain(titled[1]).replace(/[:.]$/, ''), text: plain(titled[2]) });
        } else {
          group.items.push({ title: '', text: plain(item[1]) });
        }
      } else if (group?.items.length && /^\s+\S/.test(line)) {
        // A line carried on, or a point under the item: part of the item.
        const last = group.items[group.items.length - 1];
        last.text = `${last.text} ${plain(line.replace(/^\s*[-*]\s+/, ''))}`.trim();
      }
    }
  }
  const groupsWithItems = [];
  for (const noteGroup of notes) {
    if (noteGroup.items.length) {
      groupsWithItems.push(noteGroup);
    }
  }
  return { summary, notes: groupsWithItems };
}

// Every release to offer, newest first, from every page of them. GitHub allows 60 requests an
// hour per IP without a token; GITHUB_TOKEN (any token, no scopes needed for a public repository)
// raises that to 5,000, and is optional.
export async function allReleases() {
  const headers = { accept: 'application/vnd.github+json', 'x-github-api-version': '2022-11-28', 'user-agent': 'fixup-links' };
  if (process.env.GITHUB_TOKEN) {
    headers.authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
  }
  const releases = [];
  for (let page = 1; page <= PAGES; page++) {
    const response = await fetch(RELEASES + page, { headers, signal: AbortSignal.timeout(10_000) });
    if (!response.ok) {
      throw new Error(`GitHub replied ${response.status}`);
    }
    const list = await response.json();
    if (!Array.isArray(list)) {
      break;
    }
    releases.push(...list);
    // The last page: GitHub names no next one.
    let linkHeader = response.headers.get('link');
    if (!linkHeader) {
      linkHeader = '';
    }
    if (!/rel="next"/.test(linkHeader)) {
      break;
    }
  }
  const offered = [];
  for (const release of releases) {
    const asOffered = asRelease(release);
    if (asOffered) {
      offered.push(asOffered);
    }
  }
  offered.sort(function (first, second) {
    if (newer(first.version, second.version)) {
      return -1;
    }
    if (newer(second.version, first.version)) {
      return 1;
    }
    return 0;
  });
  return offered;
}

// The newest release to offer, or null while there's none.
export async function latestRelease() {
  const releases = await allReleases();
  if (releases[0]) {
    return releases[0];
  }
  return null;
}
