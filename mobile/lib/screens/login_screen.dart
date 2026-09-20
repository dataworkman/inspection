import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_card.dart';

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
  bool _busy = false;
  bool _showPassword = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final auth = context.read<AuthState>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await auth.login(_email.text.trim(), _password.text);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notice = context.watch<AuthState>().notice;
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Icon(Icons.fact_check_outlined,
                            color: Colors.white, size: 32),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text('Store Inspection',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall),
                    const SizedBox(height: AppSpacing.xs),
                    Text('Sign in to continue',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: AppColors.textMuted)),
                    const SizedBox(height: AppSpacing.xl),
                    AppCard(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (notice != null && _error == null) ...[
                            _Banner(
                                message: notice,
                                tone: Tone.info,
                                icon: Icons.info_outline),
                            const SizedBox(height: AppSpacing.lg),
                          ],
                          if (_error != null) ...[
                            _Banner(
                                message: _error!,
                                tone: Tone.danger,
                                icon: Icons.error_outline),
                            const SizedBox(height: AppSpacing.lg),
                          ],
                          TextField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.username],
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.mail_outline),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          TextField(
                            controller: _password,
                            obscureText: !_showPassword,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.password],
                            onSubmitted: (_) => _busy ? null : _login(),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                tooltip: _showPassword
                                    ? 'Hide password'
                                    : 'Show password',
                                icon: Icon(_showPassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined),
                                onPressed: () => setState(
                                    () => _showPassword = !_showPassword),
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          FilledButton(
                            onPressed: _busy ? null : _login,
                            child: _busy
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2.5, color: Colors.white),
                                  )
                                : const Text('Log in'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner(
      {required this.message, required this.tone, required this.icon});

  final String message;
  final Tone tone;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = toneColors(tone);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: colors.foreground),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(message,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: colors.foreground)),
          ),
        ],
      ),
    );
  }
}
