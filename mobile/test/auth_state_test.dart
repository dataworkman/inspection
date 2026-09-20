import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:store_inspection_mobile/api/api_client.dart';
import 'package:store_inspection_mobile/auth/auth_state.dart';

/// Scripted API: answers by "METHOD path" and records what was asked.
class ScriptedApiClient extends ApiClient {
  ScriptedApiClient() : super(baseUrl: 'http://example.test');

  final requests = <String>[];
  final Map<String, Object> responses = {};

  Future<Map<String, dynamic>> _answer(String method, String path) async {
    requests.add('$method $path');
    final answer = responses['$method $path'];
    if (answer is Exception) throw answer;
    return (answer as Map<String, dynamic>?) ?? {};
  }

  @override
  Future<Map<String, dynamic>> get(String path) => _answer('GET', path);

  @override
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) =>
      _answer('POST', path);

  @override
  Future<Map<String, dynamic>> delete(String path) => _answer('DELETE', path);
}

const _inspector = {'id': 5, 'role': 'inspector', 'name': 'Inspector'};

void main() {
  late ScriptedApiClient api;
  late List<String> events;
  late AuthState auth;

  AuthState build() => AuthState(
        api,
        onSignedIn: (id) async => events.add('in:$id'),
        onSignedOut: ({required sessionExpired}) =>
            events.add(sessionExpired ? 'out:expired' : 'out:logout'),
      );

  setUp(() {
    api = ScriptedApiClient();
    events = [];
    SharedPreferences.setMockInitialValues({});
    auth = build();
  });

  Future<SharedPreferences> prefs() => SharedPreferences.getInstance();

  group('restore', () {
    test('a valid session loads the user and remembers it', () async {
      SharedPreferences.setMockInitialValues({'api_token': 't'});
      api.responses['GET /me'] = {'user': _inspector};

      await auth.restore();

      expect(auth.signedIn, isTrue);
      expect(auth.userId, 5);
      expect(jsonDecode((await prefs()).getString('user')!), _inspector);
      expect(events, ['in:5']);
      expect(auth.loading, isFalse);
    });

    test('being offline keeps the session and uses the remembered user',
        () async {
      SharedPreferences.setMockInitialValues(
          {'api_token': 't', 'user': jsonEncode(_inspector)});
      api.responses['GET /me'] = ApiException('Cannot reach the server', 0);

      await auth.restore();

      expect(auth.signedIn, isTrue);
      expect(auth.role, 'inspector');
      expect((await prefs()).getString('api_token'), 't');
      expect(events, ['in:5']);
    });

    test('a server error keeps the session too', () async {
      SharedPreferences.setMockInitialValues(
          {'api_token': 't', 'user': jsonEncode(_inspector)});
      api.responses['GET /me'] = ApiException('Request failed (502)', 502);

      await auth.restore();

      expect(auth.signedIn, isTrue);
    });

    test('offline without a remembered user cannot continue', () async {
      SharedPreferences.setMockInitialValues({'api_token': 't'});
      api.responses['GET /me'] = ApiException('Cannot reach the server', 0);

      await auth.restore();

      expect(auth.signedIn, isFalse);
      expect((await prefs()).getString('api_token'), isNull);
      expect(auth.loading, isFalse);
    });

    test('a rejected token clears the stale session', () async {
      SharedPreferences.setMockInitialValues(
          {'api_token': 'expired', 'user': jsonEncode(_inspector)});
      api.responses['GET /me'] = ApiException('invalid or missing token', 401);

      await auth.restore();
      final preferences = await prefs();

      expect(auth.loading, isFalse);
      expect(auth.signedIn, isFalse);
      expect(auth.user, isNull);
      expect(api.token, isNull);
      expect(preferences.getString('api_token'), isNull);
      expect(preferences.getString('user'), isNull);
      expect(events, isEmpty);
    });
  });

  group('login and logout', () {
    test('login stores the session and announces the user', () async {
      api.responses['POST /auth/login'] = {'token': 'abc', 'user': _inspector};
      auth.notice = 'old notice';

      await auth.login('a@b.c', 'pw');

      expect(api.token, 'abc');
      expect(auth.notice, isNull);
      expect((await prefs()).getString('api_token'), 'abc');
      expect(jsonDecode((await prefs()).getString('user')!), _inspector);
      expect(events, ['in:5']);
    });

    test('logout revokes the token on the server and clears everything',
        () async {
      api.responses['POST /auth/login'] = {'token': 'abc', 'user': _inspector};
      await auth.login('a@b.c', 'pw');
      events.clear();

      await auth.logout();

      expect(api.requests, contains('DELETE /auth/logout'));
      expect(auth.signedIn, isFalse);
      expect(auth.user, isNull);
      expect((await prefs()).getString('api_token'), isNull);
      expect((await prefs()).getString('user'), isNull);
      expect(events, ['out:logout']);
    });

    test('logging out works while offline', () async {
      api.responses['POST /auth/login'] = {'token': 'abc', 'user': _inspector};
      await auth.login('a@b.c', 'pw');
      api.responses['DELETE /auth/logout'] =
          ApiException('Cannot reach the server', 0);
      events.clear();

      await auth.logout();

      expect(auth.signedIn, isFalse);
      expect(events, ['out:logout']);
    });
  });

  group('expired session', () {
    Future<void> signIn() async {
      api.responses['POST /auth/login'] = {'token': 'abc', 'user': _inspector};
      await auth.login('a@b.c', 'pw');
      events.clear();
    }

    test('signs out with an explanation', () async {
      await signIn();

      api.onUnauthorized!();
      await Future<void>.delayed(Duration.zero);

      expect(auth.signedIn, isFalse);
      expect(auth.notice, contains('session expired'));
      expect(events, ['out:expired']);
    });

    test('a burst of rejected requests ends the session only once', () async {
      await signIn();

      api.onUnauthorized!();
      api.onUnauthorized!();
      api.onUnauthorized!();
      await Future<void>.delayed(Duration.zero);

      expect(events, ['out:expired']);
    });

    test('is ignored when nobody is signed in', () async {
      api.onUnauthorized!();
      await Future<void>.delayed(Duration.zero);

      expect(events, isEmpty);
      expect(auth.notice, isNull);
    });
  });
}
