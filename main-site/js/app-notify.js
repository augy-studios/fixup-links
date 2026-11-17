/* Notifications, in the Android app only: the bell in the Edge Tray opens a window with two
   switches, new versions of the app and news from uwuFix. Each is an FCM topic the app joins
   (FixupPlugin.setTopic), so the server keeps no list of phones: new versions are pushed by
   api/push/release.js when a release is published, and news is sent from the Firebase console
   (flutter/FIREBASE-SETUP.md).

   Turning one on asks Android's notification permission first (Android 13 and later), through
   Capacitor's PushNotifications plugin. Nothing is asked until a switch is turned on.

   The bell only shows when the app was built with Firebase (google-services.json). The website
   and PWA have no notifications, as before. */
'use strict';

(function () {
  if (!window.AppBridge?.native) {
    return;
  }

  const NOTES = {
    denied: "Notifications are off for uwuFix in Android's settings. Turn them on there, then come back.",
    offline: "Couldn't reach Firebase. Check you're online, then try again.",
  };

  let switches = [];

  function note(text, { settings = false } = {}) {
    const paragraph = document.getElementById('notifyNote');
    if (text) {
      paragraph.textContent = text;
    } else {
      paragraph.textContent = '';
    }
    paragraph.hidden = !text;
    document.getElementById('notifySettingsBtn').hidden = !settings;
  }

  /** Whether notifications are allowed, asking Android for permission if it hasn't been decided yet. */
  async function allowed() {
    const now = await AppBridge.call('PushNotifications', 'checkPermissions');
    if (now.receive === 'granted') {
      return true;
    }
    // Once refused for good, Android won't prompt again: its settings are the only way.
    if (now.receive === 'denied') {
      return false;
    }
    const after = await AppBridge.call('PushNotifications', 'requestPermissions');
    return after.receive === 'granted';
  }

  /** Sets the switches from the topics the app has joined, and says so if Android has notifications off. */
  async function refresh() {
    note('');
    try {
      const [topics, permission] = await Promise.all([
        AppBridge.call('Fixup', 'topics'),
        AppBridge.call('PushNotifications', 'checkPermissions'),
      ]);
      for (const input of switches) {
        input.checked = !!topics[input.dataset.topic];
      }
      // Turned on here, then switched off in Android's settings: say why nothing arrives.
      if ((topics.releases || topics.news) && permission.receive !== 'granted') {
        note(NOTES.denied, { settings: true });
      }
    } catch {
      // The switches stay as drawn.
    }
  }

  /** Joins or leaves a switch's topic, asking for permission first when turning one on. */
  async function toggle(input) {
    const on = input.checked;
    input.disabled = true;
    note('');
    try {
      if (on && !(await allowed())) {
        input.checked = false;
        note(NOTES.denied, { settings: true });
        return;
      }
      await AppBridge.call('Fixup', 'setTopic', { topic: input.dataset.topic, on });
    } catch (error) {
      input.checked = !on;
      if (error?.message) {
        note(error.message);
      } else {
        note(NOTES.offline);
      }
    } finally {
      input.disabled = false;
    }
  }

  AppBridge.ready(5000).then(function (inApp) {
    if (!inApp || AppBridge.quick() || !AppBridge.has('push')) {
      return;
    }
    switches = [...document.querySelectorAll('#notifyModal [data-topic]')];
    for (const input of switches) {
      input.addEventListener('change', function () {
        toggle(input);
      });
    }

    const bell = document.getElementById('notifyBtn');
    bell.hidden = false;
    bell.addEventListener('click', function () {
      refresh();
      openModal('notifyModal');
    });

    document.getElementById('notifySettingsBtn').addEventListener('click', function () {
      AppBridge.call('Fixup', 'openSettings', { what: 'notifications' }).catch(function () {});
    });
    // Back from Android's settings with the window still open.
    document.addEventListener('visibilitychange', function () {
      if (document.visibilityState === 'visible' && !document.getElementById('notifyModal').classList.contains('hidden')) {
        refresh();
      }
    });
  });
})();
