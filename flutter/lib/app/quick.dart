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
  State<QuickScreen> createState() {
    return _QuickScreenState();
  }
}

class _QuickScreenState extends State<QuickScreen> {
  String _text = '';
  String? _link;
  bool _replace = false;
  NativeListener? _subscription;

  @override
  void initState() {
    super.initState();
    final quick = Native.info?['quick'] as Map?;
    if (quick == null) {
      _take(<String, dynamic>{});
    } else {
      _take(Map<String, dynamic>.from(quick));
    }
    _subscription = Native.on('Fixup', 'quick', _take);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  /// What the quick screen was opened with: the text, whether Replace is offered, and the link
  /// in it, cleaned at once (or the text itself, tried as one).
  void _take(Map<String, dynamic> quick) {
    final sharedText = quick['text'];
    String text;
    if (sharedText == null) {
      text = '';
    } else {
      text = '$sharedText';
    }
    setState(() {
      _text = text;
      _replace = quick['replace'] == true;
      _link = extractUrlFromText(text);
    });
    if (_link != null) {
      Fixer.I.fix(_link);
    } else if (text.trim().isNotEmpty) {
      Fixer.I.input.text = text.trim();
      Fixer.I.fix();
    }
  }

  void _finish(String? text) {
    Native.call('Fixup', 'finish', {'text': ?text}).catchError((_) {
      return null;
    });
  }

  /// Replace, when it's offered and there's a clean link: the sentence with the link swapped in.
  VoidCallback? _replaceAction() {
    if (_replace && Fixer.I.cleaned != null) {
      return () {
        _finish(replaceLinkInText(_text, _link, Fixer.I.cleaned!));
      };
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.fx;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close),
          onPressed: () {
            _finish(null);
          },
        ),
        title: const Text('Fix link'),
        actions: [
          TextButton(
            onPressed: () {
              Native.call('Fixup', 'open', {'url': 'https://fixup.uwuapps.org/'}).catchError((_) {
                return null;
              });
            },
            child: Text('Open uwuFix', style: TextStyle(color: palette.brandInk)),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        ListenableBuilder(
          listenable: Fixer.I,
          builder: (context, _) {
            return CleanerCard(onReplace: _replaceAction());
          },
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: () {
              _finish(null);
            },
            child: const Text('Done'),
          ),
        ),
      ]),
    );
  }
}

/// Whether the app was opened as the quick screen.
bool get isQuick {
  return Native.info?['quick'] is Map;
}

/// Back, in the quick screen: back to the app it came over.
void quickBack() {
  AppNav.say('');
  Native.call('Fixup', 'finish').catchError((_) {
    return null;
  });
}
