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
  static bool _ours(String k) => k == 'uwufix_history' || k.startsWith('uwufix.') || k.startsWith('tour.') || k == 'uwufix_theme';

  /// How many keys came across (0 when there was nothing, or it was done before).
  static Future<int> run() async {
    final store = Store.I;
    if (store.has(doneKey) || !Native.available) return 0;
    var count = 0;
    try {
      final got = await Native.call('Migrate', 'read');
      final items = (got?['items'] as Map?) ?? const {};
      for (final e in items.entries) {
        final k = '${e.key}', v = e.value;
        if (!_ours(k) || v is! String || store.has(k)) continue;
        store.put(k, v);
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
