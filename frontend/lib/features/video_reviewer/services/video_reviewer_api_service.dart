import 'dart:async';
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

  Future<VideoReviewerApiResult> submitMigrationUpload({
    required List<String> targetFiles,
    required bool migrateFiles,
    bool? madeForKids,
    String? visibilitySetting,
    String? uploadName,
  }) async {
    final Map<String, dynamic> payload = <String, dynamic>{
      'target_files': targetFiles,
      'migrate_files': migrateFiles,
    };
    if (madeForKids != null) {
      payload['made_for_kids'] = madeForKids;
    }
    if (visibilitySetting != null && visibilitySetting.trim().isNotEmpty) {
      payload['visibility_setting'] = visibilitySetting.trim();
    }
    if (uploadName != null && uploadName.trim().isNotEmpty) {
      payload['upload_name'] = uploadName.trim();
    }

    final http.Response response = await http.post(
      _apiUri('/api/migration/upload_file_paths'),
      headers: <String, String>{'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    return VideoReviewerApiResult(
      statusCode: response.statusCode,
      json: _decodeJsonMap(response.body),
    );
  }

  Future<VideoReviewerApiResult> getKeepLocalStatuses({
    required List<String> targetFiles,
  }) async {
    final http.Response response = await http.post(
      _apiUri('/api/migration/are_files_marked_to_keep_local'),
      headers: <String, String>{'Content-Type': 'application/json'},
      body: jsonEncode(<String, dynamic>{'target_files': targetFiles}),
    );
    return VideoReviewerApiResult(
      statusCode: response.statusCode,
      json: _decodeJsonMap(response.body),
    );
  }

  Future<VideoReviewerApiResult> setKeepLocalDesignation({
    required List<String> targetFiles,
    required bool designation,
  }) async {
    final http.Response response = await http.post(
      _apiUri('/api/migration/mark_to_keep_local'),
      headers: <String, String>{'Content-Type': 'application/json'},
      body: jsonEncode(<String, dynamic>{
        'target_files': targetFiles,
        'designation': designation,
      }),
    );
    return VideoReviewerApiResult(
      statusCode: response.statusCode,
      json: _decodeJsonMap(response.body),
    );
  }

  Stream<Map<String, dynamic>> streamMigrationUploadStatus({
    required String jobId,
  }) async* {
    final http.Client client = http.Client();
    try {
      final Uri uri = _apiUri(
        '/api/migration/upload_status_stream',
        queryParameters: <String, String>{'job_id': jobId},
      );
      final http.StreamedResponse response = await client.send(
        http.Request('GET', uri),
      );
      if (response.statusCode >= 400) {
        final String body = await response.stream.bytesToString();
        final Map<String, dynamic> errorJson = _decodeJsonMap(body);
        throw Exception(
          (errorJson['error'] ?? 'Failed to stream upload status').toString(),
        );
      }

      String? eventName;
      final List<String> dataLines = <String>[];
      await for (final String line in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (line.isEmpty) {
          if (dataLines.isNotEmpty) {
            final String data = dataLines.join('\n');
            final Map<String, dynamic> payload = _decodeJsonMap(data);
            if (eventName != null && eventName.isNotEmpty) {
              payload['_event'] = eventName;
            }
            yield payload;
          }
          eventName = null;
          dataLines.clear();
          continue;
        }
        if (line.startsWith('event:')) {
          eventName = line.substring(6).trim();
          continue;
        }
        if (line.startsWith('data:')) {
          dataLines.add(line.substring(5).trimLeft());
        }
      }
    } finally {
      client.close();
    }
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
