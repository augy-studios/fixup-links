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

const _deniedMessage = "Notifications are off for uwuFix in Android's settings. Turn them on there, then come back.";
const _offlineMessage = "Couldn't reach Firebase. Check you're online, then try again.";

/// Pushes that arrive while the app's in front: FCM leaves showing them to the app.
void listenForPushes() {
  if (!Native.has('push')) {
    return;
  }
  Native.on('PushNotifications', 'pushNotificationReceived', (message) {
    Map<dynamic, dynamic> rawData = const {};
    final givenData = message['data'] as Map?;
    if (givenData != null) {
      rawData = givenData;
    }
    final data = Map<String, dynamic>.from(rawData);
    String title = '';
    final rawTitle = message['title'];
    if (rawTitle != null) {
      title = '$rawTitle';
    }
    if (data['type'] == 'release' && Native.has('update')) {
      String text;
      if (title.isEmpty) {
        text = 'A new version of uwuFix is out.';
      } else {
        text = title;
      }
      String version = '';
      final rawVersion = data['version'];
      if (rawVersion != null) {
        version = '$rawVersion';
      }
      AppNav.say(
        text,
        action: 'Update',
        onAction: () {
          AppUpdate.openPage(version: version);
        },
      );
    } else if (title.isNotEmpty) {
      final body = message['body'];
      if (body == null) {
        AppNav.say(title);
      } else {
        AppNav.say('$title: $body');
      }
    }
  });
}

/// Opens the notifications sheet from the bottom of the screen.
Future<void> showNotifySheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) {
      return const _NotifySheet();
    },
  );
}

/// The sheet with the two notification switches.
class _NotifySheet extends StatefulWidget {
  const _NotifySheet();

  @override
  State<_NotifySheet> createState() {
    return _NotifySheetState();
  }
}

class _NotifySheetState extends State<_NotifySheet> with WidgetsBindingObserver {
  /// Which topics the phone has joined.
  Map<String, bool> _enabled = {'releases': false, 'news': false};

  /// Topics being turned on or off right now.
  final Set<String> _busy = {};
  String? _note;

  /// Whether to show the button that opens Android's settings.
  bool _showSettingsButton = false;

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
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  /// Reads which topics are joined and whether notifications are allowed.
  Future<void> _refresh() async {
    try {
      final topics = await Native.call('Fixup', 'topics');
      final permissions = await Native.call('PushNotifications', 'checkPermissions');
      if (!mounted) {
        return;
      }
      setState(() {
        _enabled = {'releases': topics?['releases'] == true, 'news': topics?['news'] == true};
        final blocked = (_enabled['releases']! || _enabled['news']!) && permissions?['receive'] != 'granted';
        if (blocked) {
          _note = _deniedMessage;
        } else {
          _note = null;
        }
        _showSettingsButton = blocked;
      });
    } catch (_) {}
  }

  /// Whether notifications are allowed, asking Android for them if it still can.
  Future<bool> _allowed() async {
    final currentPermissions = await Native.call('PushNotifications', 'checkPermissions');
    if (currentPermissions?['receive'] == 'granted') {
      return true;
    }
    // Once refused for good, Android won't prompt again: its settings are the only way.
    if (currentPermissions?['receive'] == 'denied') {
      return false;
    }
    final answer = await Native.call('PushNotifications', 'requestPermissions', {
      'permissions': ['receive'],
    });
    return answer?['receive'] == 'granted';
  }

  /// Joins or leaves [topic], asking for the permission first when turning it on.
  Future<void> _toggle(String topic, bool on) async {
    setState(() {
      _busy.add(topic);
      _enabled[topic] = on;
      _note = null;
      _showSettingsButton = false;
    });
    try {
      if (on && !await _allowed()) {
        setState(() {
          _enabled[topic] = false;
          _note = _deniedMessage;
          _showSettingsButton = true;
        });
        return;
      }
      await Native.call('Fixup', 'setTopic', {'topic': topic, 'on': on});
    } on NativeError catch (error) {
      setState(() {
        _enabled[topic] = !on;
        if (error.message.isEmpty) {
          _note = _offlineMessage;
        } else {
          _note = error.message;
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy.remove(topic);
        });
      }
    }
  }

  /// What a topic's switch does when flipped: nothing while it's busy.
  ValueChanged<bool>? _onChangedFor(String topic) {
    if (_busy.contains(topic)) {
      return null;
    }
    return (value) {
      _toggle(topic, value);
    };
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.fx;
    final note = _note;
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
                value: _enabled['releases']!,
                onChanged: _onChangedFor('releases'),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('News from uwuFix'),
              subtitle: const Text('Now and then: new sites it fixes, and other news'),
              value: _enabled['news']!,
              onChanged: _onChangedFor('news'),
            ),
            if (note != null) ...[const SizedBox(height: 8), Text(note, style: TextStyle(color: palette.error))],
            if (_showSettingsButton)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () {
                    Native.call('Fixup', 'openSettings', {'what': 'notifications'}).catchError((_) {
                      return null;
                    });
                  },
                  child: const Text("Open Android's settings"),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
