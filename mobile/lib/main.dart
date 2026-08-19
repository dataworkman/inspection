import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'api/api_client.dart';
import 'auth/auth_state.dart';
import 'drafts/local_draft_storage.dart';
import 'inspections/inspection_state.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';

void main() {
  const baseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://100.107.174.72:3002');
  final apiClient = ApiClient(baseUrl: baseUrl);

  runApp(StoreInspectionApp(apiClient: apiClient));
}

class StoreInspectionApp extends StatelessWidget {
  const StoreInspectionApp({super.key, required this.apiClient});

  final ApiClient apiClient;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthState(apiClient)..restore()),
        ChangeNotifierProvider(create: (_) => InspectionState(apiClient, LocalDraftStorage())),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Store Inspection',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff61735a)),
          useMaterial3: true,
        ),
        home: Consumer<AuthState>(
          builder: (context, auth, _) {
            if (auth.loading) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            return auth.signedIn ? const HomeScreen() : const LoginScreen();
          },
        ),
      ),
    );
  }
}
