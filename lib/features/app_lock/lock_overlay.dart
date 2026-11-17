import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/utils/recovery_key.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_field.dart';
import '../../core/widgets/change_motion.dart';
import '../../core/widgets/app_logo_tile.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/status_banner.dart';
import '../../features/auth/widgets/auth_ui.dart';
import '../../features/mascot/capy.dart';
import '../../features/mascot/capy_spots.dart';
import '../../infrastructure/offline/connectivity_signal.dart';
import '../../services/encryption_service.dart';
import 'app_lock_controller.dart';
import 'app_lock_platform.dart';
import 'create_pin_screen.dart';
import 'widgets/pin_pad.dart';

class LockOverlay extends ConsumerStatefulWidget {
  const LockOverlay({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<LockOverlay> createState() => _LockOverlayState();
}

enum _LockStep { unlock, forgot, create }

class _LockOverlayState extends ConsumerState<LockOverlay>
    with WidgetsBindingObserver {
  _LockStep _step = _LockStep.unlock;
  final _recoveryInput = TextEditingController();
  bool _obscured = true;
  bool _checking = false;
  bool _promptAttempted = false;
  bool _biometricAvailable = false;
  String? _fieldError;
  int _wrongKey = 0; // E1: each wrong recovery key shakes the field once
  String? _cardError;
  Timer? _waitTicker;
  bool _navCanPop = false;
  // Mascot (spec §G1): only reads what the lock already has (P1).
  int _pinDigits = 0;
  bool _wrongPin = false;
  Timer? _wrongPinTimer;

  @override
  void initState() {
    super.initState();
    // Added before the Router's back dispatcher (this state is its parent),
    // so a locked back press reaches us first and never pops a route (E6).
    WidgetsBinding.instance.addObserver(this);
    ref.listenManual<AppLockState>(appLockProvider, (previous, next) {
      if (next.locked && !(previous?.locked ?? false)) {
        _beginUnlock();
      } else if (!next.locked && _step != _LockStep.unlock) {
        _showUnlock();
      }
      if (next.locked) _startWaitTicker();
      if (next.locked != (previous?.locked ?? false)) _syncSystemBack();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(appLockProvider).locked) {
        _syncSystemBack();
        _beginUnlock();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _waitTicker?.cancel();
    _wrongPinTimer?.cancel();
    _recoveryInput.dispose();
    super.dispose();
  }

  void _startWaitTicker() {
    _waitTicker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !ref.read(appLockProvider.notifier).isWaiting()) {
        _waitTicker?.cancel();
        _waitTicker = null;
        if (mounted) setState(() {});
      } else {
        setState(() {});
      }
    });
  }

  Future<void> _beginUnlock() async {
    _showUnlock();
    FocusManager.instance.primaryFocus?.unfocus();
    final config =
        ref.read(appLockProvider).config ??
        await ref.read(appLockProvider.notifier).readConfig();
    final available = await ref.read(appLockPlatformProvider).isAvailable();
    if (!mounted) return;
    setState(() {
      _biometricAvailable = available;
      _promptAttempted = false;
    });
    if (config?.bio == true && available) await _promptBiometric();
  }

  Future<void> _promptBiometric() async {
    if (_promptAttempted || !mounted) return;
    _promptAttempted = true;
    await ref.read(appLockProvider.notifier).authenticateWithBiometrics();
  }

  void _showUnlock() {
    if (!mounted) return;
    setState(() {
      _step = _LockStep.unlock;
      _fieldError = null;
      _cardError = null;
      _pinDigits = 0;
      _recoveryInput.clear();
    });
    _startWaitTicker();
  }

  Future<bool> _unlock(String pin) async {
    final ok = await ref.read(appLockProvider.notifier).unlockWithPin(pin);
    if (ok && mounted) _showUnlock();
    if (!ok && mounted) {
      setState(() => _wrongPin = true);
      _wrongPinTimer?.cancel();
      _wrongPinTimer = Timer(const Duration(milliseconds: 1200), () {
        if (mounted) setState(() => _wrongPin = false);
      });
    }
    return ok;
  }

  Future<void> _checkRecoveryKey() async {
    if (_checking) return;
    final input = _recoveryInput.text;
    final parsed = parseRecoveryKey(input);
    if (parsed == null && !RegExp(r'^\d{6}$').hasMatch(input)) {
      setState(
        () => _fieldError =
            'A recovery key has 25 letters and numbers. Check that you have all of it.',
      );
      return;
    }
    final online = ref.read(isOnlineProvider).valueOrNull ?? true;
    if (!online) return;
    // G2: resets share the PIN's wait, so the old 6-digit backup PIN can't
    // be guessed here faster than the app PIN.
    final lock = ref.read(appLockProvider.notifier);
    final waiting = await lock.waitingNow();
    if (!mounted) return;
    if (waiting) {
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
          setState(() {
            _checking = false;
            _step = _LockStep.create;
            _fieldError = null;
            _cardError = null;
          });
        case RestoreResult.wrongSecret:
          await ref.read(appLockProvider.notifier).registerWrongAttempt();
          if (!mounted) return;
          setState(() {
            _checking = false;
            _wrongKey++;
            _fieldError =
                "That doesn't match your backup. Check for typos and try again.";
          });
        case RestoreResult.noBackup:
          await _showRecoveryCard(
            'This account has no recovery key, so the PIN can\'t be reset. The only way back in is to clear Kuch Bhi\'s storage in your phone\'s settings and sign in again. Your old messages would be lost.',
          );
        case RestoreResult.unsupported:
          await _showRecoveryCard(
            'This backup was made by a newer version of Kuch Bhi. Update the app, then try again.',
          );
      }
    } catch (e) {
      debugPrint('[AppLock] backup check failed: ${e.runtimeType}');
      if (mounted) await _showRecoveryCard(forgotPinErrorCopy(e));
    }
  }

  Future<void> _showRecoveryCard(String message) async {
    if (!mounted) return;
    setState(() {
      _checking = false;
      _cardError = message;
    });
  }

  void _openForgot() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _step = _LockStep.forgot;
      _fieldError = null;
      _cardError = null;
      _recoveryInput.clear();
    });
  }

  // E6: while locked Android handles back itself (the app goes to the
  // background). The default predictive-back gesture calls navigator.pop()
  // on the hidden route directly, so didPopRoute alone can't stop it.
  void _syncSystemBack() {
    final locked = ref.read(appLockProvider).locked;
    SystemNavigator.setFrameworkHandlesBack(!locked && _navCanPop);
  }

  bool _onNavigation(NavigationNotification n) {
    _navCanPop = n.canHandlePop;
    if (!ref.read(appLockProvider).locked) return false;
    _syncSystemBack();
    return true;
  }

  @override
  Future<bool> didPopRoute() async {
    if (!ref.read(appLockProvider).locked) return false;
    if (_step != _LockStep.unlock) {
      _showUnlock();
    } else {
      await ref.read(appLockPlatformProvider).moveTaskToBack();
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appLockProvider);
    final gate = state.locked || state.covered;
    return Stack(
      fit: StackFit.expand,
      children: [
        NotificationListener<NavigationNotification>(
          onNotification: _onNavigation,
          child: Offstage(offstage: gate, child: widget.child),
        ),
        if (state.covered && !state.locked) const _PrivacyCover(),
        if (state.locked) _lockedContent(state),
      ],
    );
  }

  Widget _lockedContent(AppLockState state) {
    final t = context.t;
    // The builder sits above the Navigator: no Material (text styles, the
    // field) and no Overlay (selection handles, tooltips) without these.
    return Material(
      color: t.bg,
      child: Overlay.wrap(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 48,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: switch (_step) {
                      _LockStep.unlock => _unlockContent(state),
                      _LockStep.forgot => _forgotContent(),
                      _LockStep.create => PinCreationFlow(
                        changeOnly: true,
                        onSaved: (pin, _) async {
                          await ref
                              .read(appLockProvider.notifier)
                              .resetPin(pin);
                          await ref
                              .read(appLockProvider.notifier)
                              .unlockWithPin(pin);
                          if (mounted) {
                            showToast(context, 'New PIN set.');
                            _showUnlock();
                          }
                        },
                      ),
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _unlockContent(AppLockState state) {
    final controller = ref.read(appLockProvider.notifier);
    final message = controller.messageFor();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Capy(
          view: CapyView.front,
          size: 72,
          pose: CapyPose.guard,
          animated: true,
          mood: _wrongPin || controller.isWaiting()
              ? CapyMood.worried
              : CapyMood.focused,
          lookX: pinLookX(_pinDigits),
        ),
        const SizedBox(height: 20),
        PinPad(
          title: 'Enter your PIN',
          onChanged: (pin) => setState(() => _pinDigits = pin.length),
          message: message,
          enabled: !controller.isWaiting(),
          showFingerprint: state.config?.bio == true && _biometricAvailable,
          onFingerprint: () =>
              ref.read(appLockProvider.notifier).authenticateWithBiometrics(),
          onCompleted: _unlock,
        ),
        AppButton(
          variant: AppButtonVariant.text,
          onPressed: _openForgot,
          child: const Text('Forgot PIN?'),
        ),
      ],
    );
  }

  Widget _forgotContent() {
    final online = ref.watch(isOnlineProvider).valueOrNull ?? true;
    final t = context.t;
    final decoration = appFieldDecoration(context, label: 'Recovery key or PIN')
        .copyWith(
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
            onPressed: () => setState(() => _obscured = !_obscured),
          ),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppLogoTile(size: 64),
        const SizedBox(height: 20),
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
          style: TextStyle(fontSize: 15, height: 22 / 15, color: t.inkSoft),
        ),
        const SizedBox(height: 20),
        ShakeOnChange(
          trigger: _wrongKey,
          child: TextField(
          controller: _recoveryInput,
          decoration: decoration,
          obscureText: _obscured,
          keyboardType: TextInputType.text,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: const [AutofillHints.password],
          style: const TextStyle(fontFamily: 'monospace', fontSize: 15),
          onChanged: (_) {
            if (_fieldError != null || _cardError != null) {
              setState(() {
                _fieldError = null;
                _cardError = null;
              });
            }
          },
        ),
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
            onPressed: online && !_checking ? _checkRecoveryKey : null,
            child: const Text('Reset PIN'),
          ),
        ),
        if (!online) const OfflineActionHint(),
        AppButton(
          variant: AppButtonVariant.text,
          onPressed: _checking ? null : _showUnlock,
          child: const Text('Back'),
        ),
      ],
    );
  }
}

class _PrivacyCover extends StatelessWidget {
  const _PrivacyCover();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.t.bg,
    child: const Center(child: AppLogoTile(size: 64)),
  );
}
