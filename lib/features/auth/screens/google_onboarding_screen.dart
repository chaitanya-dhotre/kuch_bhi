import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/tokens.dart';
import '../../../infrastructure/services/auth_onboarding_service.dart';
import '../../auth/providers/auth_provider.dart';

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
  late final TextEditingController _usernameController;
  late final TextEditingController _displayNameController;
  bool _isLoading = false;
  String? _errorMessage;
  String? _usernameError;
  File? _pickedImage;

  @override
  void initState() {
    super.initState();
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
    _usernameController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  void _validateUsername(String value) {
    setState(() {
      if (value.isEmpty) {
        _usernameError = 'Username is required';
      } else if (value.length < 3) {
        _usernameError = 'Username must be at least 3 characters';
      } else if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value)) {
        _usernameError = 'Only letters, numbers, and underscore allowed';
      } else {
        _usernameError = null;
      }
    });
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1024,
    );
    if (picked != null && mounted) {
      setState(() => _pickedImage = File(picked.path));
    }
  }

  /// After the PB account has been created by the Google auth hook, push
  /// the optional avatar as a separate update. Avatar upload is best-effort:
  /// if it fails we just continue — the user can set it later from
  /// Edit Profile.
  Future<void> _uploadAvatarIfPicked(String userId) async {
    final image = _pickedImage;
    if (image == null) return;
    try {
      await ref.read(authOnboardingServiceProvider).uploadAvatar(
            userId: userId,
            image: image,
          );
      // Refresh local user cache so the avatar renders immediately.
      ref.invalidate(authProvider);
    } catch (e) {
      debugPrint('[Onboarding] Avatar upload failed (non-fatal): $e');
    }
  }

  Future<void> _submit() async {
    if (_usernameError != null || _usernameController.text.trim().isEmpty) {
      _validateUsername(_usernameController.text);
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await ref.read(authProvider.notifier).registerWithGoogle(
            idToken: widget.idToken,
            displayName: _displayNameController.text.trim(),
            username: _usernameController.text.trim(),
          );

      if (!mounted) return;

      if (result != null && result.user != null) {
        // Account created and authenticated. Best-effort avatar upload,
        // then let the router's redirect pick backupPinSetup or home.
        await _uploadAvatarIfPicked(result.user!.id);
        if (!mounted) return;
        context.go(AppRoutes.splash);
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Google registration failed. Please try again.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Registration failed: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final initial = _displayNameController.text.trim().isNotEmpty
        ? _displayNameController.text.trim()[0].toUpperCase()
        : '?';

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 32),

                // ── Logo ──
                Container(
                  width: 64,
                  height: 64,
                  margin: const EdgeInsets.symmetric(horizontal: 130),
                  decoration: BoxDecoration(
                    color: context.t.accent,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.lock_person_outlined,
                      color: context.t.onAccent,
                      size: 32,
                    ),
                  ),
                ).animate().scale(delay: 100.ms, duration: 400.ms),
                const SizedBox(height: 24),

                Text(
                  'Complete your profile',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),

                Text(
                  'We found your Google account. Pick a username, display name, and photo to start using Kuch Bhi.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                        height: 1.4,
                      ),
                ),
                const SizedBox(height: 28),

                // ── Avatar picker ──
                Center(
                  child: GestureDetector(
                    onTap: _isLoading ? null : _pickAvatar,
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colorScheme.surfaceContainerHighest,
                            border: Border.all(
                              color: colorScheme.onSurface
                                  .withValues(alpha: 0.1),
                              width: 2,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: _pickedImage != null
                              ? Image.file(
                                  _pickedImage!,
                                  fit: BoxFit.cover,
                                )
                              : Center(
                                  child: Text(
                                    initial,
                                    style: TextStyle(
                                      fontSize: 36,
                                      fontWeight: FontWeight.w600,
                                      color: context.t.accent,
                                    ),
                                  ),
                                ),
                        ),
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: context.t.accent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            Icons.camera_alt_outlined,
                            color: context.t.onAccent,
                            size: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // ── Email (read-only) ──
                Text(
                  'Email',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface.withValues(alpha: 0.65),
                      ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: colorScheme.onSurface.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.email_outlined, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.email,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                        ),
                      ),
                      const Icon(Icons.lock_outline, size: 18),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── Display name ──
                Text(
                  'Display name',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface.withValues(alpha: 0.65),
                      ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _displayNameController,
                  textInputAction: TextInputAction.next,
                  onChanged: (v) => setState(() {}), // update initial
                  decoration: InputDecoration(
                    hintText: 'Your name',
                    prefixIcon: const Icon(Icons.person_outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: colorScheme.onSurface.withValues(alpha: 0.08),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: colorScheme.onSurface.withValues(alpha: 0.08),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Username ──
                Text(
                  'Username',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface.withValues(alpha: 0.65),
                      ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _usernameController,
                  textInputAction: TextInputAction.done,
                  onChanged: _validateUsername,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    hintText: 'Choose a username',
                    prefixIcon: const Icon(Icons.alternate_email_outlined),
                    errorText: _usernameError,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: colorScheme.onSurface.withValues(alpha: 0.08),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: colorScheme.onSurface.withValues(alpha: 0.08),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                ),

                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.t.error,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ).animate().shake(),
                ],

                const SizedBox(height: 28),

                // ── Submit button ──
                FilledButton(
                  onPressed: _isLoading ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: context.t.accent,
                    foregroundColor: context.t.onAccent,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isLoading
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: context.t.onAccent,
                          ),
                        )
                      : const Text(
                          'Create account',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),

                const SizedBox(height: 16),

                // ── Back button ──
                TextButton(
                  onPressed: _isLoading ? null : () => context.pop(),
                  child: Text(
                    'Back',
                    style: TextStyle(
                      color: colorScheme.onSurface.withValues(alpha: 0.4),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
