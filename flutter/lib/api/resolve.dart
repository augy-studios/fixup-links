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

  /// A GET of one of the site's JSON endpoints: its answer as a map, or null when the server
  /// didn't answer 200 or didn't answer with a JSON object.
  static Future<Map<String, dynamic>?> getJson(String path, {Duration timeout = const Duration(seconds: 12)}) async {
    if (fake != null) {
      return fake!(path);
    }
    final response = await http.get(Uri.parse('$site$path'), headers: {'accept': 'application/json', 'user-agent': userAgent}).timeout(timeout);
    if (response.statusCode != 200) {
      return null;
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    return null;
  }

  /// For tests: answers posts instead of the network (throw an ApiError to refuse one).
  static Future<Map<String, dynamic>?> Function(String path, Map<String, dynamic> body)? fakePost;

  /// A JSON post (Report a bug's /api/bug-report): its answer, or an ApiError with the server's
  /// status and its "error", if it said one.
  static Future<Map<String, dynamic>?> post(String path, Map<String, dynamic> body, {Duration timeout = const Duration(seconds: 45)}) async {
    if (fakePost != null) {
      return fakePost!(path, body);
    }
    final response = await http
        .post(Uri.parse('$site$path'), headers: {'accept': 'application/json', 'content-type': 'application/json', 'user-agent': userAgent}, body: jsonEncode(body))
        .timeout(timeout);
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {}
    Map<String, dynamic>? answer;
    if (decoded is Map) {
      answer = Map<String, dynamic>.from(decoded);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      var errorMessage = '';
      if (answer?['error'] is String) {
        errorMessage = answer!['error'] as String;
      }
      throw ApiError(response.statusCode, errorMessage);
    }
    return answer;
  }
}

class ApiError implements Exception {
  ApiError(this.status, this.message);
  final int status;
  final String message;

  @override
  String toString() {
    return 'ApiError($status, $message)';
  }
}

/// A link's page title and where it really goes, or null (offline, or nothing to say): script.js's
/// fetchMetadata.
Future<({String? title, String? finalUrl})?> fetchMetadata(String url) async {
  try {
    final json = await Api.getJson('/api/resolve?url=${Uri.encodeComponent(url)}');
    if (json == null) {
      return null;
    }
    String? title;
    if (json['title'] is String && (json['title'] as String).isNotEmpty) {
      title = json['title'] as String;
    }
    String? finalUrl;
    if (json['finalUrl'] is String && (json['finalUrl'] as String).isNotEmpty) {
      finalUrl = json['finalUrl'] as String;
    }
    if (title == null && finalUrl == null) {
      return null;
    }
    return (title: title, finalUrl: finalUrl);
  } catch (_) {
    return null;
  }
}
