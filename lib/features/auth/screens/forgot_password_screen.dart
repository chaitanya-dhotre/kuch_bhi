import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/page_app_bar.dart';
import '../../../infrastructure/offline/connectivity_signal.dart';
import '../providers/auth_provider.dart';
import '../widgets/auth_text_field.dart';
import '../widgets/auth_ui.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _busy = false;
  String? _sentTo;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy) return;
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final email = _emailController.text.trim();
    setState(() => _busy = true);
    final error =
        await ref.read(authProvider.notifier).requestPasswordReset(email);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (error == null) _sentTo = email;
    });
    if (error != null) showToast(context, error, error: true);
  }

  void _backToSignIn() {
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
      appBar: pageAppBar(context, 'Reset password'),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: kAuthGutter),
          child: _sentTo == null ? _form(online) : _sent(_sentTo!),
        ),
      ),
    );
  }

  Widget _form(bool online) => Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Text(
              "Enter your account email and we'll send a link to set a new "
              'password.',
              style: authBodyStyle(context),
            ),
            const SizedBox(height: 24),
            AuthTextField(
              controller: _emailController,
              label: 'Email',
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.email],
              onEditingComplete: online ? _send : null,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Enter your email';
                if (!v.contains('@')) return 'Enter a valid email';
                return null;
              },
            ),
            const SizedBox(height: 24),
            OfflineDim(
              online: online,
              child: AppButton(
                expanded: true,
                busy: _busy,
                onPressed: online ? _send : null,
                child: const Text('Send link'),
              ),
            ),
            if (!online) const OfflineActionHint(),
            const SizedBox(height: 32),
          ],
        ),
      );

  Widget _sent(String email) {
    final t = context.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration:
                BoxDecoration(color: t.accentSoft, shape: BoxShape.circle),
            child: Icon(Icons.mark_email_read_outlined, size: 32, color: t.ink),
          ),
        ),
        const SizedBox(height: 24),
        const AuthTitle('Check your email'),
        const SizedBox(height: 8),
        Text(
          'If an account exists for $email, a reset link is on its way. It '
          'opens a web page where you choose a new password.',
          textAlign: TextAlign.center,
          style: authBodyStyle(context),
        ),
        const SizedBox(height: 32),
        AppButton(
          expanded: true,
          onPressed: _backToSignIn,
          child: const Text('Back to sign in'),
        ),
        const SizedBox(height: 8),
        AppButton(
          variant: AppButtonVariant.text,
          onPressed: () => setState(() => _sentTo = null),
          child: const Text('Send again'),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}
