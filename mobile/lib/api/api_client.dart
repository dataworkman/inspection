import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

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

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    final response = await http.post(_uri(path), headers: _headers, body: jsonEncode(body));
    return _decode(response);
  }

  Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> body) async {
    final response = await http.patch(_uri(path), headers: _headers, body: jsonEncode(body));
    return _decode(response);
  }

  Future<Map<String, dynamic>> uploadPhoto({
    required File file,
    required int responseId,
    String? annotationJson,
    String? comment,
  }) async {
    final request = http.MultipartRequest('POST', _uri('/inspection_responses/$responseId/photos'));
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.fields['photo[comment]'] = comment ?? '';
    request.fields['photo[annotation_data]'] = annotationJson ?? '{}';
    request.files.add(await http.MultipartFile.fromPath('photo[original_image]', file.path));
    request.files.add(await http.MultipartFile.fromPath('photo[annotated_image]', file.path));

    final response = await http.Response.fromStream(await request.send());
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    final body = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(body['error']?.toString() ?? 'Request failed', response.statusCode);
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
