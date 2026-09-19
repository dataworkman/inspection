import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';

class AuthState extends ChangeNotifier {
  AuthState(this.apiClient, {this.onSignedIn, this.onSignedOut}) {
    apiClient.onUnauthorized = _handleUnauthorized;
  }

  static const _tokenKey = 'api_token';
  static const _userKey = 'user';

  final ApiClient apiClient;

  /// Called once the signed-in user is known (login or a restored session).
  final Future<void> Function(int userId)? onSignedIn;

  /// Called after signing out. [sessionExpired] is true when the server
  /// rejected the token rather than the user choosing to log out.
  final void Function({required bool sessionExpired})? onSignedOut;

  Map<String, dynamic>? user;
  bool loading = true;

  /// Explains why the user is back at the login screen (shown once).
  String? notice;

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
        await preferences.setString(_userKey, jsonEncode(user));
      } catch (error) {
        if (error is ApiException && error.statusCode == 401) {
          await _clearSession(preferences);
        } else {
          // Offline or the server is having a moment: that says nothing about
          // the session, so keep it and use what we remembered about the user.
          user = _cachedUser(preferences);
          if (user == null) await _clearSession(preferences);
        }
      }
    }
    loading = false;
    notifyListeners();
    final id = userId;
    if (id != null) await onSignedIn?.call(id);
  }

  Future<void> login(String email, String password) async {
    final payload = await apiClient.post('/auth/login', {
      'auth': {'email': email, 'password': password},
    });
    apiClient.token = payload['token'] as String;
    user = payload['user'] as Map<String, dynamic>;
    notice = null;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_tokenKey, apiClient.token!);
    await preferences.setString(_userKey, jsonEncode(user));
    notifyListeners();
    await onSignedIn?.call(userId!);
  }

  /// Signs out this device. The server is told so the token stops working, but
  /// being offline never prevents signing out locally.
  Future<void> logout() async {
    if (apiClient.token != null) {
      try {
        await apiClient.delete('/auth/logout');
      } catch (_) {}
    }
    await _endSession(sessionExpired: false);
  }

  void _handleUnauthorized() {
    if (!signedIn) return;
    // Drop the token right away so a burst of 401s only ends the session once.
    apiClient.token = null;
    user = null;
    notice = 'Your session expired. Please sign in again.';
    _endSession(sessionExpired: true);
  }

  Future<void> _endSession({required bool sessionExpired}) async {
    final preferences = await SharedPreferences.getInstance();
    await _clearSession(preferences);
    onSignedOut?.call(sessionExpired: sessionExpired);
    notifyListeners();
  }

  Future<void> _clearSession(SharedPreferences preferences) async {
    await preferences.remove(_tokenKey);
    await preferences.remove(_userKey);
    apiClient.token = null;
    user = null;
  }

  Map<String, dynamic>? _cachedUser(SharedPreferences preferences) {
    final raw = preferences.getString(_userKey);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
