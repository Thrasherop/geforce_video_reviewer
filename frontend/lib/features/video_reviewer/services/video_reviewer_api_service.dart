import 'dart:convert';

import 'package:http/http.dart' as http;

const String _apiBaseUrl = String.fromEnvironment('API_BASE_URL');

class VideoReviewerApiResult {
  const VideoReviewerApiResult({
    required this.statusCode,
    required this.json,
  });

  final int statusCode;
  final Map<String, dynamic> json;

  bool get hasError => statusCode >= 400 || json['error'] != null;

  String errorOr(String fallbackMessage) {
    final dynamic error = json['error'];
    if (error == null) {
      return fallbackMessage;
    }
    return error.toString();
  }
}

class VideoReviewerApiService {
  Future<VideoReviewerApiResult> loadFiles({
    required String directory,
    required bool includeReviewed,
  }) async {
    final Uri uri = _apiUriFromRelative(
      Uri(
        path: '/api/files',
        queryParameters: <String, String>{
          'dir': directory,
          'include_reviewed': includeReviewed.toString(),
        },
      ),
    );
    final http.Response response = await http.get(uri);
    return VideoReviewerApiResult(
      statusCode: response.statusCode,
      json: _decodeJsonMap(response.body),
    );
  }

  Future<VideoReviewerApiResult> submitAction(Map<String, dynamic> payload) async {
    final http.Response response = await http.post(
      _apiUri('/api/action'),
      headers: <String, String>{'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    return VideoReviewerApiResult(
      statusCode: response.statusCode,
      json: _decodeJsonMap(response.body),
    );
  }

  Future<VideoReviewerApiResult> submitHistoryAction({
    required String endpoint,
    required String directory,
    required String path,
  }) async {
    final http.Response response = await http.post(
      _apiUri(endpoint),
      headers: <String, String>{'Content-Type': 'application/json'},
      body: jsonEncode(<String, dynamic>{'dir': directory, 'path': path}),
    );
    return VideoReviewerApiResult(
      statusCode: response.statusCode,
      json: _decodeJsonMap(response.body),
    );
  }

  Uri videoUri(String path) {
    return _apiUriFromRelative(
      Uri(path: '/api/video', queryParameters: <String, String>{'path': path}),
    );
  }

  Uri thumbnailUri(String path) {
    return _apiUriFromRelative(
      Uri(path: '/api/thumbnail', queryParameters: <String, String>{'path': path}),
    );
  }

  Uri _apiUri(String path, {Map<String, String>? queryParameters}) {
    return _apiUriFromRelative(
      Uri(path: path, queryParameters: queryParameters),
    );
  }

  Uri _apiUriFromRelative(Uri relativeUri) {
    final String base = _apiBaseUrl.trim();
    if (base.isEmpty) {
      return relativeUri;
    }
    return Uri.parse(base).resolveUri(relativeUri);
  }

  Map<String, dynamic> _decodeJsonMap(String body) {
    if (body.trim().isEmpty) {
      return <String, dynamic>{};
    }
    final dynamic decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return <String, dynamic>{'error': 'Unexpected response format'};
  }
}
