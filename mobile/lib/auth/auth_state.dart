import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';

class AuthState extends ChangeNotifier {
  AuthState(this.apiClient);

  static const _tokenKey = 'api_token';

  final ApiClient apiClient;
  Map<String, dynamic>? user;
  bool loading = true;

  bool get signedIn => apiClient.token != null;
  bool get isAdmin => user?['role'] == 'admin';
  int? get userId => user?['id'] as int?;
  String? get role => user?['role'] as String?;

  Future<void> restore() async {
    final preferences = await SharedPreferences.getInstance();
    apiClient.token = preferences.getString(_tokenKey);
    if (apiClient.token != null) {
      try {
        final payload = await apiClient.get('/me');
        user = payload['user'] as Map<String, dynamic>;
      } catch (_) {
        await preferences.remove(_tokenKey);
        apiClient.token = null;
        user = null;
      }
    }
    loading = false;
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    final payload = await apiClient.post('/auth/login', {
      'auth': {'email': email, 'password': password},
    });
    apiClient.token = payload['token'] as String;
    user = payload['user'] as Map<String, dynamic>;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_tokenKey, apiClient.token!);
    notifyListeners();
  }

  Future<void> logout() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_tokenKey);
    apiClient.token = null;
    user = null;
    notifyListeners();
  }
}
