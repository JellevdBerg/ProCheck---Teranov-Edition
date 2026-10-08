import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../widgets/app_logo.dart';
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
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: AppLogo(size: 64)),
                  const SizedBox(height: 16),
                  Text(
                    'ProCheck — Teranov Edition',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _usernameController,
                    decoration: const InputDecoration(labelText: 'Username'),
                    autocorrect: false,
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                        ? 'Enter a username'
                        : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    decoration: const InputDecoration(labelText: 'Password'),
                    obscureText: true,
                    validator: (value) => (value == null || value.length < 6)
                        ? 'At least 6 characters'
                        : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  if (_errorText != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _errorText!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _isSubmitting ? null : _submit,
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Sign in'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
