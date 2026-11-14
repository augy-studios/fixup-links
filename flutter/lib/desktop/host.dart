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

class DesktopHost implements NativeHost {
  DesktopHost(this.version);
  final String version;

  @override
  List<String> get features => const ['open', 'notify', 'background', 'releases', 'desktop'];

  @override
  Future<Map<String, dynamic>?> call(String plugin, String method, Map<String, dynamic> options) async {
    switch ('$plugin.$method') {
      case 'Fixup.info':
        // Report a bug's "Windows 11 · 10.0 (Build 26300)" (features/bug/bug_report.dart).
        return {'version': version, 'quick': null, 'desktop': true, 'os': Platform.operatingSystem, 'osVersion': Platform.operatingSystemVersion};
      case 'Fixup.open':
        final url = '${options['url'] ?? ''}';
        if (!url.startsWith('http')) throw NativeError('Only web links can be opened.');
        final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        if (!ok) throw NativeError('Nothing here opens that link.');
        return null;
      case 'Fixup.share':
        await Clipboard.setData(ClipboardData(text: '${options['url'] ?? options['text'] ?? ''}'));
        return {'copied': true};
      case 'Fixup.notify':
        await DeskNotify.show('${options['title'] ?? ''}', '${options['body'] ?? ''}', payload: options['payload'] as String?);
        return null;
      case 'Fixup.background':
        await Desktop.hide();
        return null;
      case 'Fixup.releases':
        return {'on': DeskSettings.get('updateNotices') != false};
      case 'Fixup.setReleases':
        DeskSettings.set('updateNotices', options['on'] == true ? null : false);
        return {'on': options['on'] == true};
    }
    throw NativeError('$plugin.$method isn’t on the desktop', code: 'unavailable');
  }
}
