// The quick screen (Android's FixActivity): a link shared to uwuFix, text highlighted anywhere
// with "Fix link" picked, or what's copied, from a widget's paste button. It opens over the app you
// were in with the link already cleaned, as the site did with ?text= in the WebView app, and Back
// returns you there.
//
// Highlighted in a box you can type in, it also offers Replace, which puts the fixed link back in
// place of the one highlighted (FixupPlugin.finish), keeping the sentence around it.
import 'package:flutter/material.dart';

import '../data/linkfix.dart';
import '../features/home/fixer.dart';
import '../features/home/home_page.dart';
import '../native/native_bridge.dart';
import '../theme/theme.dart';
import 'nav.dart';

class QuickScreen extends StatefulWidget {
  const QuickScreen({super.key});

  @override
  State<QuickScreen> createState() => _QuickScreenState();
}

class _QuickScreenState extends State<QuickScreen> {
  String _text = '';
  String? _link;
  bool _replace = false;
  NativeListener? _sub;

  @override
  void initState() {
    super.initState();
    _take(Map<String, dynamic>.from((Native.info?['quick'] as Map?) ?? const {}));
    _sub = Native.on('Fixup', 'quick', _take);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _take(Map<String, dynamic> q) {
    final text = '${q['text'] ?? ''}';
    setState(() {
      _text = text;
      _replace = q['replace'] == true;
      _link = extractUrlFromText(text);
    });
    if (_link != null) {
      Fixer.I.fix(_link);
    } else if (text.trim().isNotEmpty) {
      Fixer.I.input.text = text.trim();
      Fixer.I.fix();
    }
  }

  void _finish(String? text) => Native.call('Fixup', 'finish', {'text': ?text}).catchError((_) => null);

  @override
  Widget build(BuildContext context) {
    final fx = context.fx;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: () => _finish(null)),
        title: const Text('Fix link'),
        actions: [
          TextButton(
            onPressed: () => Native.call('Fixup', 'open', {'url': 'https://fixup.uwuapps.org/'}).catchError((_) => null),
            child: Text('Open uwuFix', style: TextStyle(color: fx.brandInk)),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        ListenableBuilder(
          listenable: Fixer.I,
          builder: (context, _) => CleanerCard(
            onReplace: _replace && Fixer.I.cleaned != null
                ? () => _finish(replaceLinkInText(_text, _link, Fixer.I.cleaned!))
                : null,
          ),
        ),
        const SizedBox(height: 12),
        Center(child: TextButton(onPressed: () => _finish(null), child: const Text('Done'))),
      ]),
    );
  }
}

/// Whether the app was opened as the quick screen.
bool get isQuick => Native.info?['quick'] is Map;

/// Back, in the quick screen: back to the app it came over.
void quickBack() {
  AppNav.say('');
  Native.call('Fixup', 'finish').catchError((_) => null);
}
