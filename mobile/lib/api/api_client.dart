import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';

class ApiClient {
  ApiClient({required this.baseUrl, this.token});

  final String baseUrl;
  String? token;

  Uri _uri(String path) => Uri.parse('$baseUrl/api/v1$path');

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<Map<String, dynamic>> get(String path) async {
    final response = await http.get(_uri(path), headers: _headers);
    return _decode(response);
  }

  Future<Map<String, dynamic>> post(
      String path, Map<String, dynamic> body) async {
    final response =
        await http.post(_uri(path), headers: _headers, body: jsonEncode(body));
    return _decode(response);
  }

  Future<Map<String, dynamic>> patch(
      String path, Map<String, dynamic> body) async {
    final response =
        await http.patch(_uri(path), headers: _headers, body: jsonEncode(body));
    return _decode(response);
  }

  Future<Map<String, dynamic>> uploadPhoto({
    required XFile file,
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
    request.files.add(http.MultipartFile.fromBytes(
      'photo[annotated_image]',
      bytes,
      filename: filename,
      contentType: mediaType,
    ));

    final response = await http.Response.fromStream(await request.send());
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    final body = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
          body['error']?.toString() ?? 'Request failed', response.statusCode);
    }
    return body;
  }
}

class ApiException implements Exception {
  ApiException(this.message, this.statusCode);

  final String message;
  final int statusCode;

  @override
  String toString() => message;
}
