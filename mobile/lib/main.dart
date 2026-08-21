import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'api/api_client.dart';
import 'auth/auth_state.dart';
import 'drafts/database_factory_initializer.dart';
import 'drafts/local_draft_storage.dart';
import 'inspections/inspection_state.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDatabaseFactory();

  const baseUrl = String.fromEnvironment('API_BASE_URL',
      defaultValue: 'http://100.107.174.72:3002');
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
        ChangeNotifierProvider(
            create: (_) => InspectionState(apiClient, LocalDraftStorage())),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Store Inspection',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xff276749),
            primary: const Color(0xff276749),
            secondary: const Color(0xff2563eb),
            tertiary: const Color(0xffb45309),
            surface: const Color(0xfffbfcf7),
          ),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xfff5f7f1),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xfffbfcf7),
            foregroundColor: Color(0xff18231f),
            elevation: 0,
            centerTitle: false,
            titleTextStyle: TextStyle(
              color: Color(0xff18231f),
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          cardTheme: CardTheme(
            elevation: 0,
            color: const Color(0xfffbfcf7),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Color(0xffdfe5d8)),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xffcfd8c7)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xffcfd8c7)),
            ),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            ),
          ),
        ),
        home: Consumer<AuthState>(
          builder: (context, auth, _) {
            if (auth.loading) {
              return const Scaffold(
                  body: Center(child: CircularProgressIndicator()));
            }
            return auth.signedIn ? const HomeScreen() : const LoginScreen();
          },
        ),
      ),
    );
  }
}
