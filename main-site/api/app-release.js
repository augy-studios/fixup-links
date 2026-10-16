// The newest release of the Android app (android/), for its update bar (js/app-update.js) and
// its own updater (UpdateActivity.java). Cached at Vercel's edge, so GitHub sees a request every
// few minutes however many phones ask.
//
//   { version, apk, size, sha256, page } (api/_release.js), or { version: null } while there's
//   no release with an APK.
//
// ?v=<version> is ignored here, but makes a URL the cache hasn't seen: the app adds it when a
// "new version is out" notification is tapped, so the release just published is read now.

import { latestRelease } from './_release.js';

export default async function handler(req, res) {
  let best;
  try {
    best = await latestRelease();
  } catch (err) {
    console.error('app-release:', err.message);
    return res.status(502).json({ error: "Couldn't reach GitHub" });
  }

  res.setHeader('Cache-Control', 'public, s-maxage=600, stale-while-revalidate=3600');
  return res.status(200).json(best || { version: null });
}
