// The newest release of the Android app (flutter/), for its update bar and its updates page
// (UpdateActivity.java). Read from the repository's GitHub Releases, tagged android-v<version> with
// the APK attached (release/README.md, api/_release.js), and cached at Vercel's edge, so GitHub
// sees a request every few minutes however many phones ask.
//
//   { version: "1.2.0", apk: "https://github.com/.../uwufix-1.2.0.apk", size: 712345,
//     sha256: "ab12…" (GitHub's checksum of the file, or null), page: the release's page,
//     date, summary, notes: what's new in it (notesOf in api/_release.js),
//     history: every release, this one first, each { version, date, summary, notes, page },
//     for the updates page's changelog (1.1.0) }
//   or { version: null, history: [] } while there's no release with an APK.
//
// ?v=<version> is ignored, but makes a URL the cache hasn't seen: the app adds it when a "new
// version is out" notification is tapped, so the release just published is read now.

import { allReleases } from './_release.js';

export default async function handler(req, res) {
  let releases;
  try {
    releases = await allReleases();
  } catch (err) {
    console.error('app-release:', err.message);
    return res.status(502).json({ error: "Couldn't reach GitHub" });
  }

  const history = releases.map(({ version, date, summary, notes, page }) => ({ version, date, summary, notes, page }));
  res.setHeader('Cache-Control', 'public, s-maxage=600, stale-while-revalidate=3600');
  return res.status(200).json(releases[0] ? { ...releases[0], history } : { version: null, history });
}
