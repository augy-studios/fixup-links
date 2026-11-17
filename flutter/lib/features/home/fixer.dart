// The cleaner's state: what's in the box, and what cleaning it gave. script.js's processUrl, for
// the home page, the quick screen, links the app is opened with and the desktop's command bar.
import 'package:flutter/material.dart';

import '../../api/resolve.dart';
import '../../data/history.dart';
import '../../data/linkfix.dart';

/// The one cleaner the whole app shares: the box's text, the cleaned link, the changes made, and
/// any error or note to show under it.
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

  /// Counts the runs, so a slow lookup from an older run doesn't overwrite a newer one.
  int _runNumber = 0;

  void clear() {
    input.clear();
    cleaned = null;
    changes = const [];
    error = null;
    note = null;
    _runNumber++;
    notifyListeners();
  }

  /// Cleans [text] (or what's in the box), keeps it in the history, then looks up its title and
  /// where it really goes, as the site does.
  Future<void> fix([String? text]) async {
    if (text != null) {
      input.text = text;
    }
    final rawText = input.text.trim();
    _runNumber++;
    final runNumber = _runNumber;
    cleaned = null;
    error = null;
    note = null;
    changes = const [];
    if (rawText.isEmpty) {
      error = 'Please enter a URL first.';
      notifyListeners();
      return;
    }
    CleanResult result;
    try {
      result = cleanUrl(rawText);
    } on LinkFixError catch (fixError) {
      error = fixError.message;
      notifyListeners();
      return;
    }
    cleaned = result.cleaned;
    changes = result.changes;
    notifyListeners();
    final entry = History.add(rawText, result.cleaned, result.platform);

    final metadata = await fetchMetadata(result.cleaned);
    if (runNumber != _runNumber || metadata == null) {
      return;
    }
    String? title = metadata.title;
    String? newCleaned;
    final finalUrl = metadata.finalUrl;
    if (finalUrl != null && isMeaningfulRedirect(result.cleaned, finalUrl) && !urlsEquivalent(finalUrl, rawText)) {
      var finalCleaned = finalUrl;
      try {
        finalCleaned = cleanUrl(finalUrl).cleaned;
      } catch (_) {}
      cleaned = finalCleaned;
      newCleaned = finalCleaned;
      String host = '';
      final parsedUrl = WhatwgUrl.tryParse(finalCleaned);
      if (parsedUrl != null) {
        host = parsedUrl.hostname;
      }
      changes = [...result.changes, Change('redirect', 'Redirects to $host')];
      notifyListeners();
      // The redirect's own title may be unreliable: the final page's, once it comes.
      if (title == null) {
        fetchMetadata(finalCleaned).then((finalMetadata) {
          if (finalMetadata?.title != null) {
            History.update(entry.id, title: finalMetadata!.title);
          }
        });
      }
    }
    if (title != null || newCleaned != null) {
      History.update(entry.id, title: title, cleaned: newCleaned);
    }
  }
}
