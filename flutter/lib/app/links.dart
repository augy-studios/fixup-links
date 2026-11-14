// Every way into the app by a link, through one Links.open (docs/flutter-android-app-spec.md §5):
// the site's own addresses (Android opens them in the app, as main-site/.well-known/assetlinks.json
// allows), uwu://fix/ links (Android's MainActivity turns them into the site's address; the desktop
// apps get them on their command line), and the desktop's command bar.
//
//   https://fixup.uwuapps.org/?url=<link>, ?link=<link>, ?text=<text with a link>   cleans it
//   https://fixup.uwuapps.org/join?id=<code>                       Share history, that code
//   uwu://fix/<link>, uwu://fix/?url=<link>, uwu://fixup/...      as the site's ?url=
//   any other web link                                            cleans it
import '../data/linkfix.dart';
import '../features/home/fixer.dart';
import '../features/sync/sync_page.dart';
import 'nav.dart';

class Links {
  Links._();

  static const host = 'fixup.uwuapps.org';

  /// What the app was opened with, or what was typed into the command bar. Whether it was one.
  static bool open(String raw) {
    final url = raw.trim();
    if (url.isEmpty) return false;
    final uwu = _fromUwu(url);
    if (uwu != null) return open(uwu);
    final u = Uri.tryParse(url);
    if (u != null && (u.scheme == 'https' || u.scheme == 'http') && u.host.toLowerCase() == host) {
      final path = u.path.replaceAll(RegExp(r'/+$'), '');
      if (path == '/join') {
        final code = u.queryParameters['id'];
        if (code != null) openJoin(code);
        return true;
      }
      final q = u.queryParameters;
      final link = q['url'] ?? q['link'] ?? extractUrlFromText(q['text']);
      AppNav.showPage('home');
      if (link != null) Fixer.I.fix(link);
      return true;
    }
    // Any other link: cleaned, as pasting it would be.
    if (extractUrlFromText(url) != null) {
      AppNav.showPage('home');
      Fixer.I.fix(extractUrlFromText(url));
      return true;
    }
    return false;
  }

  /// uwu://fix/... as the site's address, as MainActivity.pageFor does it, or null.
  static String? _fromUwu(String raw) {
    final m = RegExp(r'^uwu://(fix|fixup)(?=[/?#]|$)', caseSensitive: false).firstMatch(raw);
    if (m == null) return null;
    final rest = raw.substring(m.end);
    if (rest.startsWith('/') && rest.length > 1 && !rest.startsWith('/?') && !rest.startsWith('/#')) {
      var link = rest.substring(1);
      if (!link.contains('://')) link = Uri.decodeComponent(link);
      return 'https://$host/?url=${Uri.encodeComponent(link)}';
    }
    final q = rest.indexOf('?');
    return 'https://$host/${q == -1 ? '' : rest.substring(q)}';
  }
}
