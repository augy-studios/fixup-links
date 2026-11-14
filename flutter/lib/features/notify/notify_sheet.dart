// Notifications, on Android, from the bell in the Edge Tray, as the site's js/app-notify.js had
// them in the WebView app: two switches, new versions of the app and news from uwuFix. Each is a
// Firebase Cloud Messaging topic the phone joins (FixupPlugin.setTopic), so the server keeps no
// list of phones: new versions are pushed by main-site/api/push/release.js the moment a release is
// published, and news is sent from the Firebase console (flutter/FIREBASE-SETUP.md).
//
// Turning one on asks Android's notification permission first (Android 13 and later). Nothing is
// asked until a switch is turned on. A push that comes while the app's open shows at the bottom
// (listenForPushes), with Update for a new version.
import 'package:flutter/material.dart';

import '../../app/nav.dart';
import '../../native/native_bridge.dart';
import '../../theme/theme.dart';
import '../update/update_bar.dart';

const _denied = "Notifications are off for uwuFix in Android's settings. Turn them on there, then come back.";
const _offline = "Couldn't reach Firebase. Check you're online, then try again.";

/// Pushes that arrive while the app's in front: FCM leaves showing them to the app.
void listenForPushes() {
  if (!Native.has('push')) return;
  Native.on('PushNotifications', 'pushNotificationReceived', (m) {
    final data = Map<String, dynamic>.from((m['data'] as Map?) ?? const {});
    final title = '${m['title'] ?? ''}';
    if (data['type'] == 'release' && Native.has('update')) {
      AppNav.say(
        title.isEmpty ? 'A new version of uwuFix is out.' : title,
        action: 'Update',
        onAction: () => AppUpdate.openPage(version: '${data['version'] ?? ''}'),
      );
    } else if (title.isNotEmpty) {
      AppNav.say(m['body'] == null ? title : '$title: ${m['body']}');
    }
  });
}

Future<void> showNotifySheet(BuildContext context) =>
    showModalBottomSheet<void>(context: context, showDragHandle: true, isScrollControlled: true, builder: (_) => const _NotifySheet());

class _NotifySheet extends StatefulWidget {
  const _NotifySheet();

  @override
  State<_NotifySheet> createState() => _NotifySheetState();
}

class _NotifySheetState extends State<_NotifySheet> with WidgetsBindingObserver {
  Map<String, bool> _on = {'releases': false, 'news': false};
  final Set<String> _busy = {};
  String? _note;
  bool _settings = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from Android's settings with the sheet still open.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      final topics = await Native.call('Fixup', 'topics');
      final perm = await Native.call('PushNotifications', 'checkPermissions');
      if (!mounted) return;
      setState(() {
        _on = {'releases': topics?['releases'] == true, 'news': topics?['news'] == true};
        final off = (_on['releases']! || _on['news']!) && perm?['receive'] != 'granted';
        _note = off ? _denied : null;
        _settings = off;
      });
    } catch (_) {}
  }

  Future<bool> _allowed() async {
    final now = await Native.call('PushNotifications', 'checkPermissions');
    if (now?['receive'] == 'granted') return true;
    // Once refused for good, Android won't prompt again: its settings are the only way.
    if (now?['receive'] == 'denied') return false;
    final after = await Native.call('PushNotifications', 'requestPermissions', {
      'permissions': ['receive'],
    });
    return after?['receive'] == 'granted';
  }

  Future<void> _toggle(String topic, bool on) async {
    setState(() {
      _busy.add(topic);
      _on[topic] = on;
      _note = null;
      _settings = false;
    });
    try {
      if (on && !await _allowed()) {
        setState(() {
          _on[topic] = false;
          _note = _denied;
          _settings = true;
        });
        return;
      }
      await Native.call('Fixup', 'setTopic', {'topic': topic, 'on': on});
    } on NativeError catch (e) {
      setState(() {
        _on[topic] = !on;
        _note = e.message.isEmpty ? _offline : e.message;
      });
    } finally {
      if (mounted) setState(() => _busy.remove(topic));
    }
  }

  @override
  Widget build(BuildContext context) {
    final fx = context.fx;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Notifications', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            // Google Play's build is updated by Play, so new versions aren't this app's to tell.
            if (Native.has('update'))
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('New versions of the app'),
                subtitle: const Text('When an update is ready to install'),
                value: _on['releases']!,
                onChanged: _busy.contains('releases') ? null : (v) => _toggle('releases', v),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('News from uwuFix'),
              subtitle: const Text('Now and then: new sites it fixes, and other news'),
              value: _on['news']!,
              onChanged: _busy.contains('news') ? null : (v) => _toggle('news', v),
            ),
            if (_note != null) ...[const SizedBox(height: 8), Text(_note!, style: TextStyle(color: fx.error))],
            if (_settings)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => Native.call('Fixup', 'openSettings', {'what': 'notifications'}).catchError((_) => null),
                  child: const Text("Open Android's settings"),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
