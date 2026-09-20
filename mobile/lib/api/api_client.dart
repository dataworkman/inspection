import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';

class ApiClient {
  ApiClient({
    required this.baseUrl,
    this.token,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  final Duration timeout;
  String? token;

  /// Called when the server rejects the token (expired or revoked session).
  /// Not called for failed logins, which are sent without a token.
  void Function()? onUnauthorized;

  Uri _uri(String path) => Uri.parse('$baseUrl/api/v1$path');

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<Map<String, dynamic>> get(String path) =>
      _request(() => _client.get(_uri(path), headers: _headers));

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) =>
      _request(() =>
          _client.post(_uri(path), headers: _headers, body: jsonEncode(body)));

  Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> body) =>
      _request(() =>
          _client.patch(_uri(path), headers: _headers, body: jsonEncode(body)));

  Future<Map<String, dynamic>> delete(String path) =>
      _request(() => _client.delete(_uri(path), headers: _headers));

  /// Sends a request and turns every transport problem into an [ApiException]
  /// with status 0, so callers can tell "no connection" from a server answer.
  Future<Map<String, dynamic>> _request(
      Future<http.Response> Function() send) async {
    final sentToken = token != null;
    final http.Response response;
    try {
      response = await send().timeout(timeout);
    } on TimeoutException {
      throw ApiException('The server took too long to respond', 0);
    } catch (_) {
      throw ApiException('Cannot reach the server', 0);
    }
    return _decode(response, sentToken: sentToken);
  }

  Future<Map<String, dynamic>> uploadPhoto({
    required XFile file,
    XFile? annotatedFile,
    required int responseId,
    String? annotationJson,
    String? comment,
  }) async {
    final request = http.MultipartRequest(
        'POST', _uri('/inspection_responses/$responseId/photos'));
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.fields['photo[comment]'] = comment ?? '';
    request.fields['photo[annotation_data]'] = annotationJson ?? '{}';
    final bytes = await file.readAsBytes();
    final filename = file.name.isEmpty ? 'inspection-photo.jpg' : file.name;
    final contentType = lookupMimeType(filename, headerBytes: bytes);
    final mediaType = contentType == null ? null : MediaType.parse(contentType);
    request.files.add(http.MultipartFile.fromBytes(
      'photo[original_image]',
      bytes,
      filename: filename,
      contentType: mediaType,
    ));

    final annotated = annotatedFile ?? file;
    final annotatedBytes =
        annotatedFile == null ? bytes : await annotated.readAsBytes();
    final annotatedFilename = annotated.name.isEmpty
        ? 'inspection-photo-annotated.png'
        : annotated.name;
    final annotatedContentType =
        lookupMimeType(annotatedFilename, headerBytes: annotatedBytes);
    final annotatedMediaType = annotatedContentType == null
        ? null
        : MediaType.parse(annotatedContentType);
    request.files.add(http.MultipartFile.fromBytes(
      'photo[annotated_image]',
      annotatedBytes,
      filename: annotatedFilename,
      contentType: annotatedMediaType,
    ));

    return _request(
        () async => http.Response.fromStream(await _client.send(request)));
  }

  Map<String, dynamic> _decode(http.Response response,
      {required bool sentToken}) {
    final status = response.statusCode;
    final failed = status < 200 || status >= 300;
    if (status == 401 && sentToken) onUnauthorized?.call();

    Map<String, dynamic>? body;
    if (response.body.isEmpty) {
      body = <String, dynamic>{};
    } else {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) body = decoded;
      } on FormatException {
        // Not JSON (for example an HTML error page from a proxy).
      }
    }

    if (failed) {
      throw ApiException(
          body?['error']?.toString() ?? 'Request failed ($status)', status);
    }
    if (body == null) {
      throw ApiException('Unexpected response from the server', status);
    }
    return body;
  }
}

class ApiException implements Exception {
  ApiException(this.message, this.statusCode);

  final String message;
  final int statusCode;

  /// True when the request never got an answer (offline, timeout, DNS...).
  bool get isNetworkError => statusCode == 0;

  @override
  String toString() => message;
}
