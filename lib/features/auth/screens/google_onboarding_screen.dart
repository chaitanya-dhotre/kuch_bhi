import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/photo_picker_badge.dart';
import '../../../infrastructure/offline/connectivity_signal.dart';
import '../../profile/screens/crop_photo_screen.dart';
import '../providers/auth_provider.dart';
import '../widgets/auth_text_field.dart';
import '../widgets/auth_ui.dart';
import 'register_screen.dart';

const kPhotoFailedCopy =
    "Your account is ready, but the photo didn't upload. Add it from Edit "
    'profile.';

class GoogleOnboardingScreen extends ConsumerStatefulWidget {
  const GoogleOnboardingScreen({
    super.key,
    required this.email,
    required this.displayName,
    required this.idToken,
  });

  final String email;
  final String displayName;
  final String idToken;

  @override
  ConsumerState<GoogleOnboardingScreen> createState() =>
      _GoogleOnboardingScreenState();
}

class _GoogleOnboardingScreenState
    extends ConsumerState<GoogleOnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  late final TextEditingController _usernameController;
  late final TextEditingController _displayNameController;
  bool _busy = false;
  bool _submitted = false;
  String? _usernameServerError;
  File? _pickedImage;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.email);
    _displayNameController = TextEditingController(text: widget.displayName);
    // Generate username prefill from email (sanitised, lowercased, ≥3 chars).
    final base = widget.email.split('@').first
        .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')
        .toLowerCase();
    _usernameController = TextEditingController(
      text: base.length < 3 ? base.padRight(3, '0') : base,
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _usernameController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    if (_busy) return;
    final cropped = await pickCroppedPhoto(context);
    if (cropped != null && mounted) setState(() => _pickedImage = cropped);
  }

  /// F7: forget the Google account so the chooser shows next time.
  Future<void> _useDifferentAccount() async {
    if (_busy) return;
    await ref.read(authProvider.notifier).forgetGoogleAccount();
    if (mounted) context.go(AppRoutes.login);
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _submitted = true);
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _usernameServerError = null;
    });
    final result = await ref.read(authProvider.notifier).registerWithGoogle(
          idToken: widget.idToken,
          displayName: _displayNameController.text.trim(),
          username: _usernameController.text.trim().toLowerCase(),
          avatarFile: _pickedImage,
        );
    if (result != null) {
      // The redirect may already have replaced this screen: toast from root.
      final ctx = mounted ? context : rootNavigatorKey.currentContext;
      if (result.photoFailed && ctx != null && ctx.mounted) {
        showToast(ctx, kPhotoFailedCopy);
      }
      // Let the router's redirect pick backupPinSetup or home.
      if (mounted) context.go(AppRoutes.splash);
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    final s = ref.read(authProvider).valueOrNull;
    if (s is! AuthError) return;
    if (s.field == 'username') {
      setState(() => _usernameServerError = s.message);
    } else {
      showToast(context, s.message, error: true);
      if (s.code == '409') context.go(AppRoutes.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final online = ref.watch(isOnlineProvider).valueOrNull ?? true;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _useDifferentAccount();
      },
      child: Scaffold(
        backgroundColor: t.bg,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: kAuthGutter),
            child: Form(
              key: _formKey,
              autovalidateMode: _submitted
                  ? AutovalidateMode.always
                  : AutovalidateMode.disabled,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 32),
                  Center(child: _avatarPicker(t)),
                  const SizedBox(height: 16),
                  const AuthTitle('Complete your profile'),
                  const SizedBox(height: 8),
                  Text(
                    'We found your Google account. Pick a name, a username '
                    'and a photo.',
                    textAlign: TextAlign.center,
                    style: authBodyStyle(context),
                  ),
                  const SizedBox(height: 24),
                  AuthTextField(
                    controller: _emailController,
                    label: 'Email',
                    readOnly: true,
                    suffixIcon:
                        Icon(Icons.lock_outline, size: 20, color: t.inkSoft),
                  ),
                  const SizedBox(height: 16),
                  AuthTextField(
                    controller: _displayNameController,
                    label: 'Display name',
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setState(() {}), // initials follow
                    validator: validateDisplayName,
                  ),
                  const SizedBox(height: 16),
                  AuthTextField(
                    controller: _usernameController,
                    label: 'Username',
                    prefixText: '@',
                    helperText: kUsernameHelper,
                    textInputAction: TextInputAction.done,
                    errorText: _usernameServerError,
                    onChanged: (_) {
                      if (_usernameServerError != null) {
                        setState(() => _usernameServerError = null);
                      }
                    },
                    validator: validateUsername,
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
                  const SizedBox(height: 8),
                  AppButton(
                    variant: AppButtonVariant.text,
                    onPressed: _busy ? null : _useDifferentAccount,
                    child: const Text('Use a different Google account'),
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

  /// F2: R1 avatar + camera badge; the whole thing is one button.
  Widget _avatarPicker(ColorTokens t) => Semantics(
        button: true,
        enabled: !_busy,
        label: _pickedImage == null ? 'Add a profile photo' : 'Change profile photo',
        excludeSemantics: true,
        child: GestureDetector(
          onTap: _busy ? null : _pickAvatar,
          child: Stack(
            children: [
              AppAvatar(
                image: _pickedImage != null ? FileImage(_pickedImage!) : null,
                initials: initialsOf(_displayNameController.text),
                radius: 48,
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: PhotoPickerBadge(onTap: _busy ? null : _pickAvatar),
              ),
            ],
          ),
        ),
      );
}
