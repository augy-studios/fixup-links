// The bridge's answers on the desktop (docs/flutter-desktop-app-spec.md §3): the shared screens ask
// Native.call and Native.has as they would a phone's Java, and this answers instead, so no screen
// needs a desktop branch. What it doesn't answer fails as an absent plugin would, and the screen's
// plain path runs.
//
//   info       { version, features, quick: null }
//   open       the browser (url_launcher)
//   share      the clipboard, "Link copied"
//   notify     a system notification (notify.dart)
//   background hide to the tray
//   releases / setReleases   New versions of the app, in the settings file (updateNotices)
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../native/native_bridge.dart';
import 'desktop.dart';
import 'notify.dart';
import 'settings.dart';

/// What the shared screens' Native.call and Native.has get on the desktop.
class DesktopHost implements NativeHost {
  DesktopHost(this.version);
  final String version;

  @override
  List<String> get features {
    return const ['open', 'notify', 'background', 'releases', 'desktop'];
  }

  /// [options][key] as text, or '' when it's missing.
  static String _text(Map<String, dynamic> options, String key) {
    final value = options[key];
    if (value == null) {
      return '';
    }
    return '$value';
  }

  /// Answers one bridge call, as the phone's plugin would; anything else fails as unavailable.
  @override
  Future<Map<String, dynamic>?> call(String plugin, String method, Map<String, dynamic> options) async {
    switch ('$plugin.$method') {
      case 'Fixup.info':
        // Report a bug's "Windows 11 · 10.0 (Build 26300)" (features/bug/bug_report.dart).
        return {'version': version, 'quick': null, 'desktop': true, 'os': Platform.operatingSystem, 'osVersion': Platform.operatingSystemVersion};
      case 'Fixup.open':
        final url = _text(options, 'url');
        if (!url.startsWith('http')) {
          throw NativeError('Only web links can be opened.');
        }
        final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        if (!opened) {
          throw NativeError('Nothing here opens that link.');
        }
        return null;
      case 'Fixup.share':
        String shared;
        if (options['url'] != null) {
          shared = _text(options, 'url');
        } else {
          shared = _text(options, 'text');
        }
        await Clipboard.setData(ClipboardData(text: shared));
        return {'copied': true};
      case 'Fixup.notify':
        await DesktopNotify.show(_text(options, 'title'), _text(options, 'body'), payload: options['payload'] as String?);
        return null;
      case 'Fixup.background':
        await Desktop.hide();
        return null;
      case 'Fixup.releases':
        return {'on': DesktopSettings.get('updateNotices') != false};
      case 'Fixup.setReleases':
        // Missing means on, so on is kept as no value at all.
        if (options['on'] == true) {
          DesktopSettings.set('updateNotices', null);
        } else {
          DesktopSettings.set('updateNotices', false);
        }
        return {'on': options['on'] == true};
    }
    throw NativeError('$plugin.$method isn’t on the desktop', code: 'unavailable');
  }
}
