import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:store_inspection_mobile/api/api_client.dart';

ApiClient clientFor(
  Future<http.Response> Function(http.Request request) handler, {
  String? token = 'secret',
  Duration timeout = const Duration(seconds: 2),
}) =>
    ApiClient(
      baseUrl: 'http://example.test',
      token: token,
      timeout: timeout,
      client: MockClient(handler),
    );

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

void main() {
  test('sends the bearer token and JSON headers', () async {
    late http.Request seen;
    final api = clientFor((request) async {
      seen = request;
      return json({'ok': true});
    });

    expect(await api.get('/stores'), {'ok': true});

    expect(seen.url.toString(), 'http://example.test/api/v1/stores');
    expect(seen.headers['Authorization'], 'Bearer secret');
    expect(seen.headers['Accept'], 'application/json');
  });

  test('delete sends a DELETE and accepts an empty response', () async {
    late http.Request seen;
    final api = clientFor((request) async {
      seen = request;
      return http.Response('', 204);
    });

    expect(await api.delete('/auth/logout'), isEmpty);
    expect(seen.method, 'DELETE');
    expect(seen.url.path, '/api/v1/auth/logout');
  });

  group('rejected token', () {
    test('a 401 with a token reports the expired session', () async {
      var expired = 0;
      final api = clientFor(
          (_) async => json({'error': 'invalid or missing token'}, 401))
        ..onUnauthorized = () => expired++;

      await expectLater(
        api.get('/me'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'status', 401)
            .having((e) => e.message, 'message', 'invalid or missing token')),
      );
      expect(expired, 1);
    });

    test('a failed login (401 without a token) is not an expired session',
        () async {
      var expired = 0;
      final api = clientFor(
        (_) async => json({'error': 'invalid email or password'}, 401),
        token: null,
      )..onUnauthorized = () => expired++;

      await expectLater(
          api.post('/auth/login', {}),
          throwsA(
              isA<ApiException>().having((e) => e.statusCode, 'status', 401)));
      expect(expired, 0);
    });
  });

  group('errors', () {
    test('no connection is a network error, not a server answer', () async {
      final api =
          clientFor((_) async => throw http.ClientException('unreachable'));

      await expectLater(
        api.get('/stores'),
        throwsA(isA<ApiException>()
            .having((e) => e.isNetworkError, 'isNetworkError', isTrue)
            .having((e) => e.message, 'message', 'Cannot reach the server')),
      );
    });

    test('a slow server times out', () async {
      final api = clientFor(
        (_) => Future.delayed(const Duration(seconds: 1), () => json({})),
        timeout: const Duration(milliseconds: 50),
      );

      await expectLater(
        api.get('/stores'),
        throwsA(isA<ApiException>()
            .having((e) => e.isNetworkError, 'isNetworkError', isTrue)
            .having((e) => e.message, 'message', contains('too long'))),
      );
    });

    test('an HTML error page from a proxy becomes a readable error', () async {
      final api = clientFor(
          (_) async => http.Response('<html>Bad gateway</html>', 502));

      await expectLater(
        api.get('/stores'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'status', 502)
            .having((e) => e.message, 'message', 'Request failed (502)')
            .having((e) => e.isNetworkError, 'isNetworkError', isFalse)),
      );
    });

    test('the server\'s error message is passed through', () async {
      final api = clientFor(
          (_) async => json({'error': 'Answer required items: Floors'}, 422));

      await expectLater(
          api.post('/inspections/1/submit', {}),
          throwsA(isA<ApiException>().having(
              (e) => e.message, 'message', 'Answer required items: Floors')));
    });

    test('a successful response that is not JSON is rejected', () async {
      final api = clientFor((_) async => http.Response('OK', 200));

      await expectLater(
        api.get('/stores'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message',
            'Unexpected response from the server')),
      );
    });
  });
}
