// Pushes to the Android app (android/) through Firebase Cloud Messaging, to a topic: the app
// joins fixup-releases and fixup-news when you turn them on with the bell in the Edge Tray
// (FixupPlugin.setTopic), so there's no list of phones to keep. api/push/release.js sends new
// versions here; news goes from the Firebase console (android/FIREBASE-SETUP.md).
//
// FCM's HTTP v1 API, with an OAuth token made from the Firebase project's service account:
// FIREBASE_SERVICE_ACCOUNT holds its JSON key, as downloaded or base64'd. The token is signed
// here with node:crypto, so there's no Google library, and kept until just before it runs out.

import { createSign } from 'node:crypto';

const TOKEN_URL = 'https://oauth2.googleapis.com/token';
const SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';
const TOKEN_MARGIN_S = 300;

let account;
let token = null;
let tokenExpires = 0;

function serviceAccount() {
  if (account !== undefined) return account;
  const raw = process.env.FIREBASE_SERVICE_ACCOUNT?.trim();
  account = null;
  if (!raw) return account;
  try {
    const json = raw.startsWith('{') ? raw : Buffer.from(raw, 'base64').toString('utf8');
    const parsed = JSON.parse(json);
    if (parsed.project_id && parsed.client_email && parsed.private_key) account = parsed;
    else console.error('[fcm] FIREBASE_SERVICE_ACCOUNT is missing project_id, client_email or private_key');
  } catch {
    console.error("[fcm] FIREBASE_SERVICE_ACCOUNT isn't the service account's JSON key");
  }
  return account;
}

export const fcmConfigured = () => Boolean(serviceAccount());

const b64url = (v) => Buffer.from(typeof v === 'string' ? v : JSON.stringify(v)).toString('base64url');

async function accessToken() {
  const now = Math.floor(Date.now() / 1000);
  if (token && now < tokenExpires - TOKEN_MARGIN_S) return token;
  const sa = serviceAccount();
  const unsigned = `${b64url({ alg: 'RS256', typ: 'JWT' })}.${b64url({
    iss: sa.client_email, scope: SCOPE, aud: TOKEN_URL, iat: now, exp: now + 3600,
  })}`;
  const signature = createSign('RSA-SHA256').update(unsigned).sign(sa.private_key).toString('base64url');
  const r = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${unsigned}.${signature}` }),
    cache: 'no-store',
  });
  const data = await r.json().catch(() => null);
  if (!r.ok || !data?.access_token) throw new Error(`Google token responded ${r.status}: ${data?.error_description || data?.error || ''}`);
  token = data.access_token;
  tokenExpires = now + (Number(data.expires_in) || 3600);
  return token;
}

// A notification to every phone on `topic` ('fixup-releases' or 'fixup-news'), on the app's
// `channel` (Notifications.java). `tag` replaces an earlier one with the same tag rather than
// stacking under it. `data` reaches the app when it's tapped (MainActivity.onNewIntent).
export async function sendToTopic(topic, { title, body, data = {}, channel, tag }) {
  if (!fcmConfigured()) throw new Error('FIREBASE_SERVICE_ACCOUNT is not set');
  const message = {
    topic,
    notification: { title, body },
    data: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)])),
    android: {
      // A day: a phone that was off for longer hears about it from the update bar instead.
      ttl: '86400s',
      notification: { channel_id: channel, tag, icon: 'ic_notification_icon' },
    },
  };

  const send = async () => fetch(`https://fcm.googleapis.com/v1/projects/${serviceAccount().project_id}/messages:send`, {
    method: 'POST',
    headers: { authorization: `Bearer ${await accessToken()}`, 'content-type': 'application/json' },
    body: JSON.stringify({ message }),
    cache: 'no-store',
  });
  let r = await send();
  // A token Google took back early: once more with a fresh one.
  if (r.status === 401) {
    token = null;
    r = await send();
  }
  if (r.ok) return;
  const detail = await r.text().catch(() => '');
  throw new Error(`FCM responded ${r.status}: ${detail.slice(0, 300)}`);
}
