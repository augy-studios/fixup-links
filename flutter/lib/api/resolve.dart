// The site's API, which the app uses as the site does: /api/resolve follows a link's redirects and
// reads its page's title (main-site/api/resolve.js), and /api/app-release says the newest version
// of the Android app.
import 'dart:convert';

import 'package:http/http.dart' as http;

const site = 'https://fixup.uwuapps.org';

class Api {
  Api._();

  /// For tests and screenshots: answers instead of the network.
  static Future<Map<String, dynamic>?> Function(String path)? fake;

  static String userAgent = 'uwuFixApp/1.1';

  static Future<Map<String, dynamic>?> getJson(String path, {Duration timeout = const Duration(seconds: 12)}) async {
    if (fake != null) return fake!(path);
    final r = await http.get(Uri.parse('$site$path'), headers: {'accept': 'application/json', 'user-agent': userAgent}).timeout(timeout);
    if (r.statusCode != 200) return null;
    final v = jsonDecode(r.body);
    return v is Map ? Map<String, dynamic>.from(v) : null;
  }

  /// For tests: answers posts instead of the network (throw an ApiError to refuse one).
  static Future<Map<String, dynamic>?> Function(String path, Map<String, dynamic> body)? fakePost;

  /// A JSON post (Report a bug's /api/bug-report): its answer, or an ApiError with the server's
  /// status and its "error", if it said one.
  static Future<Map<String, dynamic>?> post(String path, Map<String, dynamic> body, {Duration timeout = const Duration(seconds: 45)}) async {
    if (fakePost != null) return fakePost!(path, body);
    final r = await http
        .post(Uri.parse('$site$path'), headers: {'accept': 'application/json', 'content-type': 'application/json', 'user-agent': userAgent}, body: jsonEncode(body))
        .timeout(timeout);
    Object? v;
    try {
      v = jsonDecode(r.body);
    } catch (_) {}
    final m = v is Map ? Map<String, dynamic>.from(v) : null;
    if (r.statusCode < 200 || r.statusCode >= 300) throw ApiError(r.statusCode, m?['error'] is String ? m!['error'] as String : '');
    return m;
  }
}

class ApiError implements Exception {
  ApiError(this.status, this.message);
  final int status;
  final String message;

  @override
  String toString() => 'ApiError($status, $message)';
}

/// A link's page title and where it really goes, or null (offline, or nothing to say): script.js's
/// fetchMetadata.
Future<({String? title, String? finalUrl})?> fetchMetadata(String url) async {
  try {
    final json = await Api.getJson('/api/resolve?url=${Uri.encodeComponent(url)}');
    if (json == null) return null;
    final title = json['title'] is String && (json['title'] as String).isNotEmpty ? json['title'] as String : null;
    final finalUrl = json['finalUrl'] is String && (json['finalUrl'] as String).isNotEmpty ? json['finalUrl'] as String : null;
    if (title == null && finalUrl == null) return null;
    return (title: title, finalUrl: finalUrl);
  } catch (_) {
    return null;
  }
}
