import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../theme/nocturne_theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/industrial/chassis_background.dart';
import '../widgets/industrial/industrial_panel.dart';
import 'app_shell.dart';

/// Username/password sign-in, shown instead of [AppShell] when no Supabase
/// session exists. No self-signup — accounts are created by an Operator
/// (see `admin_screen.dart`), not by whoever opens the app, so this is
/// sign-in only. No email anywhere in this UI — each username maps to a
/// synthetic address under the hood (see `auth_provider.dart`'s
/// `emailForUsername`).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isSubmitting = false;
  String? _errorText;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });

    final auth = ref.read(authControllerProvider);
    try {
      await auth.signIn(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const AppShell()));
    } on AuthException catch (e) {
      setState(() => _errorText = e.message);
    } catch (e) {
      // supabase_flutter can throw its own exception types here (e.g. a
      // network-level AuthException that isn't an AuthApiException, or a
      // connectivity error) that don't match the catch above — without
      // this, those fell through silently: the spinner reset and nothing
      // else happened, with no indication anything had gone wrong.
      setState(() => _errorText = 'Sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.nocturne;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const ChassisBackground(),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppLogo(size: 56),
                    const SizedBox(height: 12),
                    Text(
                      'ProCheck',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Teranov Edition',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: tokens.neutral400,
                        letterSpacing: 0.06,
                      ),
                    ),
                    const SizedBox(height: 28),
                    IndustrialPanel(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Sign in',
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 20),
                              TextFormField(
                                controller: _usernameController,
                                decoration: const InputDecoration(
                                  labelText: 'Username',
                                  prefixIcon: Icon(Icons.person_outline, size: 20),
                                ),
                                autocorrect: false,
                                validator: (value) =>
                                    (value == null || value.trim().isEmpty)
                                    ? 'Enter a username'
                                    : null,
                                onFieldSubmitted: (_) => _submit(),
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _passwordController,
                                decoration: const InputDecoration(
                                  labelText: 'Password',
                                  prefixIcon: Icon(Icons.lock_outline, size: 20),
                                ),
                                obscureText: true,
                                validator: (value) =>
                                    (value == null || value.length < 6)
                                    ? 'At least 6 characters'
                                    : null,
                                onFieldSubmitted: (_) => _submit(),
                              ),
                              if (_errorText != null) ...[
                                const SizedBox(height: 14),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.error.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      NocturneRadius.sm,
                                    ),
                                  ),
                                  child: Text(
                                    _errorText!,
                                    style: TextStyle(
                                      color: theme.colorScheme.error,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 22),
                              SizedBox(
                                height: 44,
                                child: FilledButton(
                                  onPressed: _isSubmitting ? null : _submit,
                                  child: _isSubmitting
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text('Sign in'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
