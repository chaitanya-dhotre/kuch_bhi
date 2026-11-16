import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/recovery_key.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/app_field.dart';
import '../../core/widgets/app_logo_tile.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/page_app_bar.dart';
import '../../core/widgets/section_header.dart';
import '../../core/widgets/settings_tile.dart';
import '../../core/widgets/status_banner.dart';
import '../../data/local/secure_storage/secure_storage_service.dart';
import '../../services/encryption_service.dart';
import '../../infrastructure/offline/connectivity_signal.dart';
import '../auth/widgets/auth_ui.dart';
import '../settings/widgets/theme_mode_group.dart';
import 'app_lock_controller.dart';
import 'app_lock_platform.dart';
import 'create_pin_screen.dart';
import 'widgets/pin_pad.dart';

class AppLockSettingsScreen extends ConsumerStatefulWidget {
  const AppLockSettingsScreen({super.key});

  @override
  ConsumerState<AppLockSettingsScreen> createState() =>
      _AppLockSettingsScreenState();
}

class _AppLockSettingsScreenState extends ConsumerState<AppLockSettingsScreen> {
  late bool _authorized;
  bool _bioSupported = false;
  bool _bioEnrolled = false;
  String? _pinMessage;
  bool _forgot = false;
  bool _checking = false;
  bool _obscured = true;
  String? _fieldError;
  String? _cardError;
  final _recoveryInput = TextEditingController();
  late Future<BackupKind?> _backupKind;
  Timer? _waitTicker;

  @override
  void initState() {
    super.initState();
    final state = ref.read(appLockProvider);
    _authorized = !state.enabled;
    _backupKind = _loadBackupKind();
    // D2 on the B4 gate: the wait line counts down and the keys stay dim.
    _waitTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted &&
          !_authorized &&
          ref.read(appLockProvider.notifier).isWaiting()) {
        setState(() {});
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkBiometrics());
  }

  Future<BackupKind?> _loadBackupKind() async {
    try {
      final userId = await ref.read(secureStorageProvider).getCurrentUserId();
      if (userId == null || userId.isEmpty) return null;
      return await ref.read(encryptionServiceProvider).tryGetBackupKind(userId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _checkBiometrics() async {
    final platform = ref.read(appLockPlatformProvider);
    final supported = await platform.isDeviceSupported();
    final enrolled =
        supported && (await platform.getAvailableBiometrics()).isNotEmpty;
    if (mounted) {
      setState(() {
        _bioSupported = supported;
        _bioEnrolled = enrolled;
      });
    }
  }

  Future<void> _unlockPage(String pin) async {
    final ok = await ref.read(appLockProvider.notifier).unlockWithPin(pin);
    if (mounted) {
      setState(
        () => _pinMessage = ok
            ? null
            : ref.read(appLockProvider.notifier).messageFor(),
      );
    }
    if (ok && mounted) setState(() => _authorized = true);
  }

  @override
  void dispose() {
    _waitTicker?.cancel();
    _recoveryInput.dispose();
    super.dispose();
  }

  void _openForgot() {
    setState(() {
      _forgot = true;
      _fieldError = null;
      _cardError = null;
      _recoveryInput.clear();
    });
  }

  Future<void> _checkRecovery() async {
    if (_checking) return;
    final input = _recoveryInput.text;
    if (parseRecoveryKey(input) == null &&
        !RegExp(r'^\d{6}$').hasMatch(input)) {
      setState(
        () => _fieldError =
            'A recovery key has 25 letters and numbers. Check that you have all of it.',
      );
      return;
    }
    final online = ref.read(isOnlineProvider).valueOrNull ?? true;
    if (!online) return;
    // G2: resets share the PIN's wait (see LockOverlay).
    final lock = ref.read(appLockProvider.notifier);
    if (lock.isWaiting()) {
      setState(() => _fieldError = lock.messageFor());
      return;
    }
    setState(() {
      _checking = true;
      _fieldError = null;
      _cardError = null;
    });
    try {
      final result = await ref
          .read(encryptionServiceProvider)
          .checkBackupSecret(input);
      if (!mounted) return;
      switch (result) {
        case RestoreResult.restored:
        case RestoreResult.restoredLegacy:
          _recoveryInput.clear();
          await Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => CreatePinScreen(
                changeOnly: true,
                successMessage: 'New PIN set.',
                onSaved: (pin, _) =>
                    ref.read(appLockProvider.notifier).resetPin(pin),
              ),
            ),
          );
          if (mounted)
            setState(() {
              _authorized = true;
              _forgot = false;
              _checking = false;
            });
        case RestoreResult.wrongSecret:
          await ref.read(appLockProvider.notifier).registerWrongAttempt();
          if (!mounted) return;
          setState(() {
            _checking = false;
            _fieldError =
                "That doesn't match your backup. Check for typos and try again.";
          });
        case RestoreResult.noBackup:
          setState(() {
            _checking = false;
            _cardError =
                "This account has no recovery key, so the PIN can't be reset. The only way back in is to clear Kuch Bhi's storage in your phone's settings and sign in again. Your old messages would be lost.";
          });
        case RestoreResult.unsupported:
          setState(() {
            _checking = false;
            _cardError =
                'This backup was made by a newer version of Kuch Bhi. Update the app, then try again.';
          });
      }
    } catch (e) {
      debugPrint('[AppLock] backup check failed: ${e.runtimeType}');
      if (mounted)
        setState(() {
          _checking = false;
          _cardError = forgotPinErrorCopy(e);
        });
    }
  }

  Future<void> _turnOn() async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => const CreatePinScreen()));
    if (mounted) setState(() {});
  }

  Future<void> _changePin() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => const CreatePinScreen(changeOnly: true),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _turnOff() async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Turn off app lock?',
      body: 'Kuch Bhi will open without a PIN.',
      confirmLabel: 'Turn off',
    );
    if (!confirmed || !mounted) return;
    try {
      await ref.read(appLockProvider.notifier).turnOff();
      if (mounted) showToast(context, 'App lock is off.');
    } catch (_) {
      if (mounted) showToast(context, "Couldn't save. Try again.", error: true);
    }
  }

  Future<void> _setBiometrics(bool value) async {
    final controller = ref.read(appLockProvider.notifier);
    if (value) {
      final ok = await controller.authenticateWithBiometrics();
      if (!ok || !mounted) return;
    }
    try {
      await controller.updateSettings(bio: value);
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) showToast(context, "Couldn't save. Try again.", error: true);
    }
  }

  Future<void> _setAfter(int seconds) async {
    try {
      await ref.read(appLockProvider.notifier).updateSettings(after: seconds);
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        setState(() {});
        showToast(context, "Couldn't save. Try again.", error: true);
      }
    }
  }

  Future<void> _setHideNames(bool value) async {
    try {
      await ref.read(appLockProvider.notifier).updateSettings(hideNames: value);
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) showToast(context, "Couldn't save. Try again.", error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appLockProvider);
    return Scaffold(
      backgroundColor: context.t.bg,
      appBar: pageAppBar(context, 'App lock'),
      body: !_authorized && state.enabled
          ? (_forgot ? _forgotGate() : _pinGate(state))
          : _settingsBody(state),
    );
  }

  Widget _pinGate(AppLockState state) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              children: [
                const AppLogoTile(size: 64),
                const SizedBox(height: 20),
                PinPad(
                  title: 'Enter your PIN',
                  message: ref.read(appLockProvider.notifier).isWaiting()
                      ? ref.read(appLockProvider.notifier).messageFor()
                      : _pinMessage,
                  enabled: !ref.read(appLockProvider.notifier).isWaiting(),
                  showFingerprint: _bioEnrolled && state.config?.bio == true,
                  onFingerprint: () => ref
                      .read(appLockProvider.notifier)
                      .authenticateWithBiometrics()
                      .then((ok) {
                        if (ok && mounted) setState(() => _authorized = true);
                      }),
                  onCompleted: (pin) async {
                    await _unlockPage(pin);
                    return _authorized;
                  },
                ),
                AppButton(
                  variant: AppButtonVariant.text,
                  onPressed: _openForgot,
                  child: const Text('Forgot PIN?'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _forgotGate() {
    final online = ref.watch(isOnlineProvider).valueOrNull ?? true;
    final t = context.t;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    'Reset your PIN',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      height: 30 / 24,
                      fontWeight: FontWeight.w700,
                      color: t.ink,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Enter your recovery key, or the 6-digit backup PIN if you set one before. Your chats and keys stay as they are.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    height: 22 / 15,
                    color: t.inkSoft,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _recoveryInput,
                  decoration:
                      appFieldDecoration(
                        context,
                        label: 'Recovery key or PIN',
                      ).copyWith(
                        error: _fieldError == null
                            ? null
                            : appFieldError(context, _fieldError!),
                        suffixIcon: IconButton(
                          tooltip: _obscured ? 'Show key' : 'Hide key',
                          icon: Icon(
                            _obscured
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: t.inkSoft,
                          ),
                          onPressed: () =>
                              setState(() => _obscured = !_obscured),
                        ),
                      ),
                  obscureText: _obscured,
                  keyboardType: TextInputType.text,
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: const [AutofillHints.password],
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 15),
                ),
                if (_cardError != null) ...[
                  const SizedBox(height: 12),
                  StatusBanner(
                    message: _cardError!,
                    leading: Icon(Icons.error_outline, color: t.error),
                  ),
                ],
                const SizedBox(height: 16),
                OfflineDim(
                  online: online,
                  child: AppButton(
                    expanded: true,
                    busy: _checking,
                    onPressed: online && !_checking ? _checkRecovery : null,
                    child: const Text('Reset PIN'),
                  ),
                ),
                if (!online) OfflineActionHint(),
                AppButton(
                  variant: AppButtonVariant.text,
                  onPressed: _checking
                      ? null
                      : () => setState(() {
                          _forgot = false;
                          _recoveryInput.clear();
                        }),
                  child: const Text('Back'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _settingsBody(AppLockState state) {
    final config = state.config;
    final t = context.t;
    if (!state.enabled || config == null) {
      return SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          children: [
            Text(
              "Ask for a PIN every time Kuch Bhi opens, so someone holding your unlocked phone can't read your chats.",
              style: TextStyle(fontSize: 15, height: 22 / 15, color: t.ink),
            ),
            const SizedBox(height: 20),
            FutureBuilder<BackupKind?>(
              future: _backupKind,
              builder: (context, snapshot) {
                if (snapshot.data != BackupKind.none)
                  return const SizedBox.shrink();
                return StatusBanner(
                  message:
                      "You don't have a recovery key yet. Without one, a forgotten PIN can only be fixed by clearing Kuch Bhi's storage, and your old messages would be lost.",
                  leading: Icon(Icons.info_outline, color: t.inkSoft),
                );
              },
            ),
            FutureBuilder<BackupKind?>(
              future: _backupKind,
              builder: (context, snapshot) => snapshot.data == BackupKind.none
                  ? AppButton(
                      variant: AppButtonVariant.text,
                      onPressed: () => context.push(AppRoutes.backupPinSetup),
                      child: const Text('Set up a recovery key'),
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: 8),
            AppButton(
              expanded: true,
              onPressed: _turnOn,
              child: const Text('Turn on app lock'),
            ),
          ],
        ),
      );
    }

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        children: [
          SettingsGroup(
            children: [
              SettingsTile(
                icon: Icons.lock_outline,
                title: 'App lock',
                trailing: Switch(
                  value: true,
                  onChanged: (_) => _turnOff(),
                ),
                onTap: _turnOff,
              ),
              SettingsTile(
                icon: Icons.pin_outlined,
                title: 'Change PIN',
                trailing: Icon(Icons.chevron_right, color: t.inkFaint),
                onTap: _changePin,
              ),
            ],
          ),
          if (_bioSupported) ...[
            const SizedBox(height: 12),
            if (_bioEnrolled)
              SettingsGroup(
                children: [
                  SettingsTile(
                    icon: Icons.fingerprint,
                    title: 'Unlock with fingerprint or face',
                    trailing: Switch(
                      value: config.bio,
                      onChanged: _setBiometrics,
                    ),
                    onTap: () => _setBiometrics(!config.bio),
                  ),
                ],
              )
            else
              Opacity(
                opacity: .38,
                child: SettingsGroup(
                  children: [
                    const SettingsTile(
                      icon: Icons.fingerprint,
                      title: 'Unlock with fingerprint or face',
                      subtitle:
                          "Add a fingerprint or face in your phone's settings first.",
                    ),
                  ],
                ),
              ),
          ],
          const SectionHeader('Lock after'),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              'Time away from Kuch Bhi before it asks again.',
              style: TextStyle(fontSize: 13, color: t.inkSoft),
            ),
          ),
          SettingsGroup(
            children: [
              for (final option in const [
                (label: 'Immediately', seconds: 0),
                (label: 'After 1 minute', seconds: 60),
                (label: 'After 5 minutes', seconds: 300),
                (label: 'After 30 minutes', seconds: 1800),
              ])
                Semantics(
                  selected: config.after == option.seconds,
                  inMutuallyExclusiveGroup: true,
                  child: SettingsTile(
                    icon: Icons.schedule_outlined,
                    title: option.label,
                    trailing: CheckDisc(
                      selected: config.after == option.seconds,
                    ),
                    onTap: () => _setAfter(option.seconds),
                  ),
                ),
            ],
          ),
          const SectionHeader('Notifications'),
          SettingsGroup(
            children: [
              SettingsTile(
                icon: Icons.visibility_off_outlined,
                title: 'Hide names in notifications',
                subtitle:
                    'Notifications say "New message" instead of who it\'s from.',
                trailing: Switch(
                  value: config.hideNames,
                  onChanged: _setHideNames,
                ),
                onTap: () => _setHideNames(!config.hideNames),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
