import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/username_rules.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/page_app_bar.dart';
import '../../../infrastructure/offline/connectivity_signal.dart';
import '../providers/auth_provider.dart';
import '../widgets/auth_text_field.dart';
import '../widgets/auth_ui.dart';

/// The one validator lives in core (audit §3.2); re-exported so existing
/// `register_screen.dart` imports keep resolving it.
export '../../../core/utils/username_rules.dart' show validateUsername;

/// D3 / F4: shared with Google onboarding.
String? validateDisplayName(String? v) {
  if (v == null || v.trim().isEmpty) return 'Enter your name';
  if (v.trim().length < 2) return 'At least 2 characters';
  return null;
}

const kUsernameHelper = 'Letters, numbers and underscores. At least 3.';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _usernameController    = TextEditingController();
  final _emailController       = TextEditingController();
  final _passwordController    = TextEditingController();
  final _confirmController     = TextEditingController();

  final _displayNameFocus = FocusNode();
  final _usernameFocus    = FocusNode();
  final _emailFocus       = FocusNode();
  final _passwordFocus    = FocusNode();
  final _confirmFocus     = FocusNode();

  bool _obscurePassword = true;
  bool _obscureConfirm  = true;
  bool _busy = false;

  /// D4: server errors on their fields until that field is edited.
  String? _usernameServerError;
  String? _emailServerError;

  @override
  void dispose() {
    _displayNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _displayNameFocus.dispose();
    _usernameFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // G5: the keyboard's Done must not bypass the disabled button.
    if (_busy || !(ref.read(isOnlineProvider).valueOrNull ?? true)) return;
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _usernameServerError = null;
      _emailServerError = null;
    });
    try {
      await ref.read(authProvider.notifier).register(
            displayName: _displayNameController.text.trim(),
            username: _usernameController.text.trim().toLowerCase(),
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
      if (!mounted) return;
      // G4: this screen reports only the action it started.
      final s = ref.read(authProvider).valueOrNull;
      if (s is AuthAuthenticated) {
        TextInput.finishAutofillContext();
      } else if (s is AuthError) {
        switch (s.field) {
          case 'username':
            setState(() => _usernameServerError = s.message);
          case 'email':
            setState(() => _emailServerError = s.message);
          default:
            showToast(context, s.message, error: true);
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toSignIn() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final online = ref.watch(isOnlineProvider).valueOrNull ?? true;

    return Scaffold(
      backgroundColor: t.bg,
      appBar: pageAppBar(context, 'Create account'),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: kAuthGutter),
          child: Form(
            key: _formKey,
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  Text('Join Kuch Bhi', style: authBodyStyle(context)),
                  const SizedBox(height: 24),
                  AuthTextField(
                    controller: _displayNameController,
                    focusNode: _displayNameFocus,
                    label: 'Display name',
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.name],
                    onEditingComplete: () =>
                        FocusScope.of(context).requestFocus(_usernameFocus),
                    validator: validateDisplayName,
                  ),
                  const SizedBox(height: 16),
                  AuthTextField(
                    controller: _usernameController,
                    focusNode: _usernameFocus,
                    label: 'Username',
                    prefixText: '@',
                    helperText: kUsernameHelper,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.newUsername],
                    errorText: _usernameServerError,
                    onChanged: (_) {
                      if (_usernameServerError != null) {
                        setState(() => _usernameServerError = null);
                      }
                    },
                    onEditingComplete: () =>
                        FocusScope.of(context).requestFocus(_emailFocus),
                    validator: validateUsername,
                  ),
                  const SizedBox(height: 16),
                  AuthTextField(
                    controller: _emailController,
                    focusNode: _emailFocus,
                    label: 'Email',
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    errorText: _emailServerError,
                    onChanged: (_) {
                      if (_emailServerError != null) {
                        setState(() => _emailServerError = null);
                      }
                    },
                    onEditingComplete: () =>
                        FocusScope.of(context).requestFocus(_passwordFocus),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Enter your email';
                      }
                      if (!v.contains('@')) return 'Enter a valid email';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  AuthTextField(
                    controller: _passwordController,
                    focusNode: _passwordFocus,
                    label: 'Password',
                    helperText: 'At least 8 characters.',
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.newPassword],
                    suffixIcon: PasswordToggle(
                      obscured: _obscurePassword,
                      onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword),
                    ),
                    onEditingComplete: () =>
                        FocusScope.of(context).requestFocus(_confirmFocus),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Enter a password';
                      if (v.length < 8) return 'At least 8 characters';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  AuthTextField(
                    controller: _confirmController,
                    focusNode: _confirmFocus,
                    label: 'Confirm password',
                    obscureText: _obscureConfirm,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.newPassword],
                    suffixIcon: PasswordToggle(
                      obscured: _obscureConfirm,
                      onPressed: () => setState(
                          () => _obscureConfirm = !_obscureConfirm),
                    ),
                    onEditingComplete: _submit,
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return 'Confirm your password';
                      }
                      if (v != _passwordController.text) {
                        return "Passwords don't match";
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  OfflineDim(
                    online: online,
                    child: AppButton(
                      expanded: true,
                      busy: _busy,
                      onPressed: online ? _submit : null,
                      child: const Text('Create account'),
                    ),
                  ),
                  if (!online) const OfflineActionHint(),
                  const SizedBox(height: 24),
                  AuthFooter(
                    prompt: 'Already have an account?',
                    action: 'Sign in',
                    onPressed: _toSignIn,
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
