import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../infrastructure/offline/connectivity_signal.dart';
import '../../mascot/capybara.dart';
import '../providers/auth_provider.dart';
import '../widgets/auth_text_field.dart';
import '../widgets/auth_ui.dart';
import '../widgets/google_sign_in_button.dart';

/// C3: which button started the running action.
enum _Busy { none, password, google }

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocus    = FocusNode();
  final _passwordFocus = FocusNode();
  bool _obscurePassword = true;
  _Busy _busy = _Busy.none;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Clear any leftover error from a previous attempt.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authProvider.notifier).clearError();
    });
  }

  bool get _online => ref.read(isOnlineProvider).valueOrNull ?? true;

  /// G4: only the action this screen started reports its error.
  void _showError() {
    final s = ref.read(authProvider).valueOrNull;
    if (s is AuthError && mounted) showToast(context, s.message, error: true);
  }

  Future<void> _submit() async {
    // G5: the keyboard's Done must not bypass the disabled button.
    if (_busy != _Busy.none || !_online) return;
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = _Busy.password);
    try {
      await ref.read(authProvider.notifier).signInWithEmailPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
      if (ref.read(authProvider).valueOrNull is AuthAuthenticated) {
        TextInput.finishAutofillContext();
      } else {
        _showError();
      }
    } finally {
      if (mounted) setState(() => _busy = _Busy.none);
    }
  }

  /// Google button:
  /// - Existing accounts → full OAuth + PB auth, splash redirect picks
  ///   the right destination (backup-pin or home) via encryptionSyncProvider.
  /// - New accounts → onboard via [GoogleOnboardingScreen] so the user
  ///   can choose username / display name / avatar before the account
  ///   is created on the server. After successful registerWithGoogle()
  ///   the redirect lands on backup-pin setup, then home.
  Future<void> _continueWithGoogle() async {
    if (_busy != _Busy.none) return;
    setState(() => _busy = _Busy.google);
    try {
      final result = await ref.read(authProvider.notifier).signInWithGoogle();
      if (!mounted) return;
      if (result == null) {
        _showError(); // a cancelled picker leaves no error: silent
        return;
      }
      if (result.needsOnboarding) {
        context.go(AppRoutes.googleOnboarding, extra: result);
        return;
      }
      // Existing account: authentication succeeded — splash + redirect.
      context.go(AppRoutes.splash);
    } finally {
      if (mounted) setState(() => _busy = _Busy.none);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final online = ref.watch(isOnlineProvider).valueOrNull ?? true;
    final idle = _busy == _Busy.none;

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: kAuthGutter),
            child: Form(
              key: _formKey,
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 48),
                    // Mascot slot (art stays swappable).
                    const Center(child: Capybara(size: Size(112, 95))),
                    const SizedBox(height: 16),
                    const AuthTitle('Welcome back'),
                    const SizedBox(height: 4),
                    Text('Sign in to continue',
                        textAlign: TextAlign.center,
                        style: authBodyStyle(context)),
                    const SizedBox(height: 32),
                    AuthTextField(
                      controller: _emailController,
                      focusNode: _emailFocus,
                      label: 'Email or username',
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [
                        AutofillHints.username,
                        AutofillHints.email,
                      ],
                      onEditingComplete: () =>
                          FocusScope.of(context).requestFocus(_passwordFocus),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Enter your email or username'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    AuthTextField(
                      controller: _passwordController,
                      focusNode: _passwordFocus,
                      label: 'Password',
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      onEditingComplete: _submit,
                      suffixIcon: PasswordToggle(
                        obscured: _obscurePassword,
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                      ),
                      validator: (v) => v == null || v.isEmpty
                          ? 'Enter your password'
                          : null,
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: AppButton(
                        variant: AppButtonVariant.text,
                        onPressed: idle
                            ? () => context.push(AppRoutes.forgotPassword)
                            : null,
                        child: const Text('Forgot password?'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    OfflineDim(
                      online: online,
                      child: AppButton(
                        expanded: true,
                        busy: _busy == _Busy.password,
                        onPressed: online && idle ? _submit : null,
                        child: const Text('Sign in'),
                      ),
                    ),
                    if (!online) const OfflineActionHint(),
                    const SizedBox(height: 24),
                    Row(children: [
                      Expanded(child: Container(height: 1, color: t.line)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('or',
                            style: TextStyle(
                                fontSize: 13,
                                height: 18 / 13,
                                color: t.inkSoft)),
                      ),
                      Expanded(child: Container(height: 1, color: t.line)),
                    ]),
                    const SizedBox(height: 24),
                    OfflineDim(
                      online: online,
                      child: GoogleSignInButton(
                        busy: _busy == _Busy.google,
                        onPressed: online && idle ? _continueWithGoogle : null,
                      ),
                    ),
                    const SizedBox(height: 32),
                    AuthFooter(
                      prompt: "Don't have an account?",
                      action: 'Create account',
                      // G4: no second screen's action while one runs.
                      onPressed:
                          idle ? () => context.push(AppRoutes.register) : null,
                    ),
                    const SizedBox(height: 32),
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
