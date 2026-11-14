// The cleaner's state: what's in the box, and what cleaning it gave. script.js's processUrl, for
// the home page, the quick screen, links the app is opened with and the desktop's command bar.
import 'package:flutter/material.dart';

import '../../api/resolve.dart';
import '../../data/history.dart';
import '../../data/linkfix.dart';

class Fixer extends ChangeNotifier {
  Fixer._();
  static final Fixer I = Fixer._();

  /// The box's text, which the home page and the quick screen draw.
  final input = TextEditingController();

  String? cleaned;
  List<Change> changes = const [];
  String? error;

  /// A note under the result, such as "You're offline".
  String? note;

  int _run = 0;

  void clear() {
    input.clear();
    cleaned = null;
    changes = const [];
    error = null;
    note = null;
    _run++;
    notifyListeners();
  }

  /// Cleans [text] (or what's in the box), keeps it in the history, then looks up its title and
  /// where it really goes, as the site does.
  Future<void> fix([String? text]) async {
    if (text != null) input.text = text;
    final raw = input.text.trim();
    final run = ++_run;
    cleaned = null;
    error = null;
    note = null;
    changes = const [];
    if (raw.isEmpty) {
      error = 'Please enter a URL first.';
      notifyListeners();
      return;
    }
    CleanResult result;
    try {
      result = cleanUrl(raw);
    } on LinkFixError catch (e) {
      error = e.message;
      notifyListeners();
      return;
    }
    cleaned = result.cleaned;
    changes = result.changes;
    notifyListeners();
    final entry = History.add(raw, result.cleaned, result.platform);

    final meta = await fetchMetadata(result.cleaned);
    if (run != _run || meta == null) return;
    String? title = meta.title;
    String? newCleaned;
    if (meta.finalUrl != null && isMeaningfulRedirect(result.cleaned, meta.finalUrl!) && !urlsEquivalent(meta.finalUrl!, raw)) {
      var finalCleaned = meta.finalUrl!;
      try {
        finalCleaned = cleanUrl(meta.finalUrl!).cleaned;
      } catch (_) {}
      cleaned = finalCleaned;
      newCleaned = finalCleaned;
      final host = WhatwgUrl.tryParse(finalCleaned)?.hostname ?? '';
      changes = [...result.changes, Change('redirect', 'Redirects to $host')];
      notifyListeners();
      // The redirect's own title may be unreliable: the final page's, once it comes.
      if (title == null) {
        fetchMetadata(finalCleaned).then((m) {
          if (m?.title != null) History.update(entry.id, title: m!.title);
        });
      }
    }
    if (title != null || newCleaned != null) History.update(entry.id, title: title, cleaned: newCleaned);
  }
}
