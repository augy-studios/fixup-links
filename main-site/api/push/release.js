// Tells phones a new version of the Android app is out, the moment it's published: GitHub calls
// this for the repository's releases (a webhook, android/FIREBASE-SETUP.md), and it pushes
// "Version 1.2.0 of uwuFix is out" to the fixup-releases topic, which the app joins when "New
// versions of the app" is turned on (js/app-notify.js). Tapping it opens the app's update window
// (MainActivity, UpdateActivity).
//
// GitHub signs each delivery with GITHUB_WEBHOOK_SECRET, checked here before anything is sent,
// so nobody else can make every phone buzz. Only "released" counts: a release published, or a
// pre-release made a full one. Drafts, pre-releases, other tags, releases without their APK, and
// a version older than the newest already out are answered with why, and nothing is sent.
//
// A web-standard handler (Request in, Response out), as the signature is over the body exactly
// as GitHub sent it, before any parsing.

import { createHmac, timingSafeEqual } from 'node:crypto';
import { sendToTopic } from '../_push/fcm.js';
import { asRelease, latestRelease, newer } from '../_release.js';

const TOPIC = 'fixup-releases';

function signedByGitHub(body, signature) {
  const secret = process.env.GITHUB_WEBHOOK_SECRET;
  if (!secret || !signature?.startsWith('sha256=')) return false;
  const expected = Buffer.from(`sha256=${createHmac('sha256', secret).update(body).digest('hex')}`);
  const given = Buffer.from(signature);
  return expected.length === given.length && timingSafeEqual(expected, given);
}

export async function POST(request) {
  const body = await request.text();
  if (!signedByGitHub(body, request.headers.get('x-hub-signature-256'))) {
    return Response.json({ error: 'Bad signature' }, { status: 401 });
  }

  const event = request.headers.get('x-github-event');
  // GitHub's hello when the webhook is first saved.
  if (event === 'ping') return Response.json({ ok: true, pong: true });
  if (event !== 'release') return Response.json({ sent: false, why: `Not a release event (${event})` });

  let payload;
  try {
    payload = JSON.parse(body);
  } catch {
    return Response.json({ error: 'Not JSON: set the webhook\'s content type to application/json' }, { status: 400 });
  }
  if (payload.action !== 'released') return Response.json({ sent: false, why: `Release ${payload.action}, not released` });

  const release = asRelease(payload.release);
  if (!release) {
    return Response.json({ sent: false, why: 'Not an android-v* release with its APK uploaded' });
  }

  // Re-publishing an old version shouldn't tell everyone it's new. GitHub's list may not show
  // this release yet, so it's only skipped when something newer is already out.
  try {
    const latest = await latestRelease();
    if (latest && newer(latest.version, release.version)) {
      return Response.json({ sent: false, why: `${latest.version} is newer than ${release.version}` });
    }
  } catch (err) {
    console.warn('push/release: could not compare with the newest release:', err.message);
  }

  try {
    await sendToTopic(TOPIC, {
      title: `Version ${release.version} of uwuFix is out`,
      body: 'Tap to update the app.',
      data: { type: 'release', version: release.version },
      channel: 'releases',
      tag: 'release',
    });
  } catch (err) {
    console.error('push/release:', err.message);
    return Response.json({ sent: false, error: err.message }, { status: 502 });
  }
  return Response.json({ sent: true, version: release.version });
}
