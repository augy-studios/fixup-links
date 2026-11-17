// The WebView app's data (1.0.0 and 1.0.1 were the site in Capacitor's WebView), brought across
// once, on the first launch after updating (docs/flutter-android-app-spec.md §2): the history,
// the theme and the Edge Tray, everything the site kept in the WebView's localStorage for
// https://fixup.uwuapps.org, read by MigratePlugin. Never over a value the app has set since, and
// the WebView's copy is left alone. Marked done by uwufix.migrated.
import '../native/native_bridge.dart';
import 'store.dart';

class Migrate {
  Migrate._();
  static const doneKey = 'uwufix.migrated';

  // The site's own keys (script.js, js/theme.js, js/tray.js, js/tour.js, js/sync.js).
  static bool _ours(String key) {
    return key == 'uwufix_history' || key.startsWith('uwufix.') || key.startsWith('tour.') || key == 'uwufix_theme';
  }

  /// How many keys came across (0 when there was nothing, or it was done before).
  static Future<int> run() async {
    final store = Store.I;
    if (store.has(doneKey) || !Native.available) {
      return 0;
    }
    var count = 0;
    try {
      final answer = await Native.call('Migrate', 'read');
      Map items = const {};
      final answerItems = answer?['items'] as Map?;
      if (answerItems != null) {
        items = answerItems;
      }
      for (final item in items.entries) {
        final key = '${item.key}';
        final value = item.value;
        if (!_ours(key) || value is! String || store.has(key)) {
          continue;
        }
        store.put(key, value);
        count++;
      }
      await Native.call('Migrate', 'done');
    } catch (_) {
      return 0; // tried again next time
    }
    store.put(doneKey, '1');
    return count;
  }
}
