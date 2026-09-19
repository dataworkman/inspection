import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_state.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Demo accounts (see README) are prefilled in debug builds only.
  final _email = TextEditingController(
      text: kDebugMode ? 'inspector@bakery-inspection.test' : '');
  final _password =
      TextEditingController(text: kDebugMode ? 'password123' : '');
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.fact_check,
                                color: Theme.of(context).colorScheme.primary),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text('Store Inspection',
                                style:
                                    Theme.of(context).textTheme.headlineSmall),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      TextField(
                          controller: _email,
                          decoration:
                              const InputDecoration(labelText: 'Email')),
                      const SizedBox(height: 12),
                      TextField(
                          controller: _password,
                          decoration:
                              const InputDecoration(labelText: 'Password'),
                          obscureText: true),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                      ],
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () async {
                          try {
                            await context
                                .read<AuthState>()
                                .login(_email.text, _password.text);
                          } catch (error) {
                            setState(() => _error = error.toString());
                          }
                        },
                        icon: const Icon(Icons.login),
                        label: const Text('Log in'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
