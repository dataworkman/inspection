import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:store_inspection_mobile/api/api_client.dart';
import 'package:store_inspection_mobile/auth/auth_state.dart';

class FailingApiClient extends ApiClient {
  FailingApiClient() : super(baseUrl: 'http://example.test');

  @override
  Future<Map<String, dynamic>> get(String path) {
    throw ApiException('Unauthorized', 401);
  }
}

void main() {
  test('restore clears stale token and finishes loading', () async {
    SharedPreferences.setMockInitialValues({'api_token': 'expired-token'});
    final apiClient = FailingApiClient();
    final auth = AuthState(apiClient);

    await auth.restore();
    final preferences = await SharedPreferences.getInstance();

    expect(auth.loading, isFalse);
    expect(auth.signedIn, isFalse);
    expect(auth.user, isNull);
    expect(apiClient.token, isNull);
    expect(preferences.getString('api_token'), isNull);
  });
}
