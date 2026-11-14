// What the result's buttons do, on whatever the app runs on: script.js's copyToClipboard,
// shareUrl, the Open button and the QR code, and the paste button.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../native/native_bridge.dart';
import '../theme/theme.dart';
import 'nav.dart';

Future<void> copyText(String text, {String said = 'Copied to clipboard'}) async {
  await Clipboard.setData(ClipboardData(text: text));
  AppNav.say(said);
}

/// What's copied, as text, or '' (Android 10 and later let only the app in front read it, which it
/// is whenever Paste can be pressed).
Future<String> pasteText() async {
  if (Native.has('paste')) {
    try {
      return '${(await Native.call('Fixup', 'paste'))?['text'] ?? ''}';
    } catch (_) {}
  }
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  return data?.text ?? '';
}

/// A link in whatever opens it: X's app for fixupx.com, or the browser.
Future<void> openLink(String url) async {
  if (Native.has('open')) {
    try {
      await Native.call('Fixup', 'open', {'url': url});
    } on NativeError catch (e) {
      AppNav.say(e.message);
    }
    return;
  }
  final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication).catchError((_) => false);
  if (!ok) AppNav.say('Nothing here opens that link.');
}

/// The share sheet on a phone; on a computer, which has none worth the name, the clipboard.
Future<void> shareLink(String url) async {
  if (Native.has('share')) {
    try {
      await Native.call('Fixup', 'share', {'url': url, 'title': 'Cleaned URL from uwuFix'});
      return;
    } catch (_) {}
  }
  await copyText(url, said: 'Link copied, ready to paste anywhere');
}

/// The QR code window, as the site's: the link in black on white, with the link under it.
Future<void> showQr(BuildContext context, String url) => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('QR Code'),
        content: SizedBox(
          width: 280,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              child: QrImageView(data: url, size: 240, backgroundColor: Colors.white, errorCorrectionLevel: QrErrorCorrectLevel.M),
            ),
            const SizedBox(height: 12),
            SelectableText(url, textAlign: TextAlign.center, style: TextStyle(color: context.fx.muted, fontSize: 13)),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
