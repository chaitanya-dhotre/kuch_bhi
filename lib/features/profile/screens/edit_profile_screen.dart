import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/utils/username_rules.dart';
import '../../../core/widgets/page_app_bar.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../core/widgets/app_field.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/photo_picker_badge.dart';
import '../../../domain/entities/user.dart';
import '../../../domain/repositories/auth_repository.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../infrastructure/offline/connectivity_signal.dart';
import '../../chat/message_offline_policy.dart';
import 'crop_photo_screen.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _aboutController = TextEditingController();
  final _touched = <String>{};
  bool _saving = false;
  bool _allowPop = false;
  bool _clearAvatar = false;
  File? _pickedImage;
  String? _takenUsername;

  // I1: the strip clears 250ms after reconnect.
  bool _stripVisible = false;
  Timer? _stripTimer;

  @override
  void initState() {
    super.initState();
    final user = _currentUser();
    if (user != null) {
      _nameController.text = user.displayName;
      _usernameController.text = user.username;
      _aboutController.text = user.about ?? '';
    }
    _stripVisible = !_online;
  }

  @override
  void dispose() {
    _stripTimer?.cancel();
    _nameController.dispose();
    _usernameController.dispose();
    _aboutController.dispose();
    super.dispose();
  }

  User? _currentUser() {
    final s = ref.read(authProvider).valueOrNull;
    return s is AuthAuthenticated ? s.user : null;
  }

  bool get _online => ref.read(isOnlineProvider).valueOrNull ?? true;

  String get _username => _usernameController.text.trim().toLowerCase();

  String? get _nameError =>
      _nameController.text.trim().isEmpty ? 'Enter a display name' : null;

  String? get _usernameError {
    final raw = _usernameController.text.trim();
    final error = validateUsername(raw);
    if (error != null) return error;
    if (_takenUsername == _username) return kUsernameTakenCopy;
    return null;
  }

  bool _dirty(User user) =>
      _nameController.text.trim() != user.displayName ||
      _username != user.username ||
      _aboutController.text.trim() != (user.about ?? '') ||
      _pickedImage != null ||
      _clearAvatar;

  void _edited(String field) => setState(() {
        _touched.add(field);
        if (field == 'username' && _takenUsername != _username) {
          _takenUsername = null;
        }
      });

  Future<void> _pickImage() async {
    if (_saving) return;
    final cropped = await pickCroppedPhoto(context);
    if (cropped != null && mounted) {
      setState(() {
        _pickedImage = cropped;
        _clearAvatar = false;
      });
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _takenUsername = null;
    });
    final timeout = Duration(seconds: _pickedImage != null ? 30 : 8);
    try {
      await ref
          .read(authProvider.notifier)
          .updateProfile(
            displayName: _nameController.text.trim(),
            username: _username,
            about: _aboutController.text.trim(),
            avatarFile: _pickedImage,
            clearAvatar: _clearAvatar,
          )
          .timeout(timeout);
      if (!mounted) return;
      showToast(context, 'Profile updated');
      Navigator.of(context).pop();
    } on UsernameTakenException {
      if (mounted) setState(() => _takenUsername = _username);
    } catch (e) {
      debugPrint('[Profile] save failed: $e');
      if (mounted) showToast(context, kSaveFailedCopy, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _onPopBlocked() async {
    if (_saving) return;
    final discard = await showConfirmDialog(
      context: context,
      title: 'Discard changes?',
      body: "Your edits won't be saved.",
      confirmLabel: 'Discard',
      cancelLabel: 'Keep editing',
    );
    if (discard == true && mounted) {
      setState(() => _allowPop = true);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    ref.listen<AsyncValue<bool>>(isOnlineProvider, (_, next) {
      final online = next.valueOrNull ?? true;
      _stripTimer?.cancel();
      if (!online) {
        setState(() => _stripVisible = true);
      } else {
        _stripTimer = Timer(const Duration(milliseconds: 250), () {
          if (mounted) setState(() => _stripVisible = false);
        });
      }
    });
    final online = ref.watch(isOnlineProvider).valueOrNull ?? true;
    final authState = ref.watch(authProvider).valueOrNull;
    final user = authState is AuthAuthenticated ? authState.user : null;
    if (user == null) {
      return Scaffold(
        backgroundColor: t.bg,
        appBar: pageAppBar(context, 'Edit profile'),
      );
    }

    final dirty = _dirty(user);
    final valid = _nameError == null && _usernameError == null;
    final canSave = dirty && valid && online && !_saving;
    final avatarUrl = _clearAvatar ? null : user.avatarUrl;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return PopScope(
      canPop: _allowPop || (!_saving && !dirty),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onPopBlocked();
      },
      child: Scaffold(
        backgroundColor: t.bg,
        appBar: pageAppBar(context, 'Edit profile', actions: [
          // I2: offline dims Save exactly once, with one hint below.
          Opacity(
            opacity: online ? 1 : .38,
            child: AppButton(
              variant: AppButtonVariant.text,
              onPressed: canSave ? _save : null,
              busy: _saving,
              child: const Text('Save'),
            ),
          ),
          const SizedBox(width: 8),
        ]),
        body: Column(
          children: [
            if (_stripVisible)
              Container(
                width: double.infinity,
                color: t.accentSoft,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.cloud_off_outlined, size: 18, color: t.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        kOfflineActionsCopy,
                        style: TextStyle(fontSize: 13, color: t.ink),
                      ),
                    ),
                  ],
                ),
              ),
            if (!online)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    kOfflineActionHint,
                    style: TextStyle(fontSize: 12, color: t.inkSoft),
                  ),
                ),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Semantics(
                        button: true,
                        label: 'Change profile photo',
                        excludeSemantics: true,
                        child: GestureDetector(
                          onTap: _pickImage,
                          child: Stack(
                            children: [
                              AnimatedSwitcher(
                                duration: reduceMotion
                                    ? Duration.zero
                                    : WarmPopTokens.motionFast,
                                child: AppAvatar(
                                  key: ValueKey(
                                      _pickedImage?.path ?? avatarUrl ?? ''),
                                  image: _pickedImage != null
                                      ? FileImage(_pickedImage!)
                                      : null,
                                  url: avatarUrl,
                                  initials: initialsOf(user.displayName),
                                  radius: 48,
                                  accentSoft: true,
                                ),
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: PhotoPickerBadge(onTap: _pickImage),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    TextField(
                      controller: _nameController,
                      readOnly: _saving,
                      maxLength: 50,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      style: TextStyle(fontSize: 15, height: 22 / 15, color: t.ink),
                      onChanged: (_) => _edited('name'),
                      decoration: appFieldDecoration(context, label: 'Display name')
                          .copyWith(
                        error: _touched.contains('name') && _nameError != null
                            ? appFieldError(context, _nameError!)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _usernameController,
                      readOnly: _saving,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.next,
                      style: TextStyle(fontSize: 15, height: 22 / 15, color: t.ink),
                      onChanged: (_) => _edited('username'),
                      decoration: appFieldDecoration(
                        context,
                        label: 'Username',
                        helper: 'Letters, numbers and underscores',
                        prefixText: '@',
                      ).copyWith(
                        error: (_touched.contains('username') ||
                                    _takenUsername != null) &&
                                _usernameError != null
                            ? appFieldError(context, _usernameError!)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _aboutController,
                      readOnly: _saving,
                      maxLength: 150,
                      maxLines: 3,
                      textInputAction: TextInputAction.done,
                      style: TextStyle(fontSize: 15, height: 22 / 15, color: t.ink),
                      onChanged: (_) => _edited('about'),
                      decoration: appFieldDecoration(
                        context,
                        label: 'About',
                        hint: 'A line about you',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
