// The Android app's releases (android/) on GitHub, tagged android-v<version> with the APK
// attached (release/README.md). Shared by api/app-release.js, which the app reads, and
// api/push/release.js, which tells phones a new one is out. Vercel doesn't serve files
// starting with _ as functions.

const RELEASES = 'https://api.github.com/repos/augy-studios/fixup-links/releases?per_page=30';
export const TAG = /^android-v(\d+(?:\.\d+)*)$/;

// Whether version a comes after version b, number by number: 1.10.0 after 1.9.0. The same as
// newer() in js/app-update.js and UpdateActivity.java.
export function newer(a, b) {
  const x = String(a).split('.').map(Number);
  const y = String(b).split('.').map(Number);
  for (let i = 0; i < Math.max(x.length, y.length); i++) {
    const d = (x[i] || 0) - (y[i] || 0);
    if (d) return d > 0;
  }
  return false;
}

// A release as the app wants it, or null if it isn't one to offer: a draft, a pre-release, a
// tag that isn't android-v*, or one published before its APK finished uploading.
//   { version: "1.2.0", apk: "https://github.com/.../uwufix-1.2.0.apk", size: 712345,
//     sha256: "ab12…" (GitHub's checksum of the file, or null), page: the release's page }
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
  };
}

// The newest release to offer, or null while there's none. GitHub allows 60 requests an hour
// per IP without a token; GITHUB_TOKEN (any token, no scopes needed for a public repository)
// raises that to 5,000, and is optional.
export async function latestRelease() {
  const headers = { accept: 'application/vnd.github+json', 'x-github-api-version': '2022-11-28', 'user-agent': 'fixup-links' };
  if (process.env.GITHUB_TOKEN) headers.authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
  const r = await fetch(RELEASES, { headers, signal: AbortSignal.timeout(10_000) });
  if (!r.ok) throw new Error(`GitHub replied ${r.status}`);
  const releases = await r.json();

  let best = null;
  for (const rel of Array.isArray(releases) ? releases : []) {
    const release = asRelease(rel);
    if (release && (!best || newer(release.version, best.version))) best = release;
  }
  return best;
}
