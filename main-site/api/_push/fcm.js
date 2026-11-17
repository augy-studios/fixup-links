// Pushes to the Android app (flutter/) through Firebase Cloud Messaging, to a topic: the app
// joins fixup-releases and fixup-news when you turn them on with the bell in the Edge Tray
// (FixupPlugin.setTopic), so there's no list of phones to keep. api/push/release.js sends new
// versions here; news goes from the Firebase console (flutter/FIREBASE-SETUP.md).
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

// The service account from FIREBASE_SERVICE_ACCOUNT (its JSON key, plain or base64'd), read once,
// or null when it's not set or isn't a usable key.
function serviceAccount() {
  if (account !== undefined) {
    return account;
  }
  const raw = process.env.FIREBASE_SERVICE_ACCOUNT?.trim();
  account = null;
  if (!raw) {
    return account;
  }
  try {
    let json;
    if (raw.startsWith('{')) {
      json = raw;
    } else {
      json = Buffer.from(raw, 'base64').toString('utf8');
    }
    const parsed = JSON.parse(json);
    if (parsed.project_id && parsed.client_email && parsed.private_key) {
      account = parsed;
    } else {
      console.error('[fcm] FIREBASE_SERVICE_ACCOUNT is missing project_id, client_email or private_key');
    }
  } catch {
    console.error("[fcm] FIREBASE_SERVICE_ACCOUNT isn't the service account's JSON key");
  }
  return account;
}

export function fcmConfigured() {
  return Boolean(serviceAccount());
}

// Text, or anything else as its JSON, in base64url (as a JWT's parts are written).
function base64Url(value) {
  let text;
  if (typeof value === 'string') {
    text = value;
  } else {
    text = JSON.stringify(value);
  }
  return Buffer.from(text).toString('base64url');
}

/**
 * An OAuth access token for FCM: a JWT signed with the service account's key, traded at Google's
 * token endpoint. Kept and reused until TOKEN_MARGIN_S before it runs out.
 */
async function accessToken() {
  const now = Math.floor(Date.now() / 1000);
  if (token && now < tokenExpires - TOKEN_MARGIN_S) {
    return token;
  }
  const serviceAccountKey = serviceAccount();
  const unsigned = `${base64Url({ alg: 'RS256', typ: 'JWT' })}.${base64Url({
    iss: serviceAccountKey.client_email, scope: SCOPE, aud: TOKEN_URL, iat: now, exp: now + 3600,
  })}`;
  const signature = createSign('RSA-SHA256').update(unsigned).sign(serviceAccountKey.private_key).toString('base64url');
  const response = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${unsigned}.${signature}` }),
    cache: 'no-store',
  });
  let data = null;
  try {
    data = await response.json();
  } catch {
    data = null;
  }
  if (!response.ok || !data?.access_token) {
    let reason = '';
    if (data?.error_description) {
      reason = data.error_description;
    } else if (data?.error) {
      reason = data.error;
    }
    throw new Error(`Google token responded ${response.status}: ${reason}`);
  }
  token = data.access_token;
  let lifetimeSeconds = Number(data.expires_in);
  if (!lifetimeSeconds) {
    lifetimeSeconds = 3600;
  }
  tokenExpires = now + lifetimeSeconds;
  return token;
}

// A notification to every phone on `topic` ('fixup-releases' or 'fixup-news'), on the app's
// `channel` (Notifications.java). `tag` replaces an earlier one with the same tag rather than
// stacking under it. `data` reaches the app when it's tapped (MainActivity.onNewIntent).
export async function sendToTopic(topic, { title, body, data = {}, channel, tag }) {
  if (!fcmConfigured()) {
    throw new Error('FIREBASE_SERVICE_ACCOUNT is not set');
  }
  // FCM takes data values as strings only.
  const stringData = {};
  for (const [key, value] of Object.entries(data)) {
    stringData[key] = String(value);
  }
  const message = {
    topic,
    notification: { title, body },
    data: stringData,
    android: {
      // A day: a phone that was off for longer hears about it from the update bar instead.
      ttl: '86400s',
      notification: { channel_id: channel, tag, icon: 'ic_notification_icon' },
    },
  };

  async function send() {
    return fetch(`https://fcm.googleapis.com/v1/projects/${serviceAccount().project_id}/messages:send`, {
      method: 'POST',
      headers: { authorization: `Bearer ${await accessToken()}`, 'content-type': 'application/json' },
      body: JSON.stringify({ message }),
      cache: 'no-store',
    });
  }
  let response = await send();
  // A token Google took back early: once more with a fresh one.
  if (response.status === 401) {
    token = null;
    response = await send();
  }
  if (response.ok) {
    return;
  }
  let detail = '';
  try {
    detail = await response.text();
  } catch {
    detail = '';
  }
  throw new Error(`FCM responded ${response.status}: ${detail.slice(0, 300)}`);
}
