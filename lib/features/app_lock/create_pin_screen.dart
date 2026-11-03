import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/page_app_bar.dart';
import 'app_lock_controller.dart';
import 'app_lock_platform.dart';
import 'widgets/pin_pad.dart';

typedef PinSaveCallback = Future<void> Function(String pin, bool bio);

class CreatePinScreen extends ConsumerStatefulWidget {
  const CreatePinScreen({
    super.key,
    this.changeOnly = false,
    this.onSaved,
    this.successMessage,
  });

  final bool changeOnly;
  final PinSaveCallback? onSaved;
  final String? successMessage;

  @override
  ConsumerState<CreatePinScreen> createState() => _CreatePinScreenState();
}

class _CreatePinScreenState extends ConsumerState<CreatePinScreen> {
  Future<void> _saveAndReport(String pin, bool bio) async {
    if (widget.onSaved != null) {
      await widget.onSaved!(pin, bio);
    } else {
      final controller = ref.read(appLockProvider.notifier);
      if (widget.changeOnly) {
        await controller.changePin(pin);
      } else {
        await controller.turnOn(pin, bio: bio);
      }
    }
    if (!mounted) return;
    showToast(
      context,
      widget.successMessage ??
          (widget.changeOnly ? 'PIN changed.' : 'App lock is on.'),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.t.bg,
      appBar: pageAppBar(
        context,
        widget.changeOnly ? 'Change PIN' : 'Create PIN',
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: PinCreationFlow(
            changeOnly: widget.changeOnly,
            onSaved: _saveAndReport,
          ),
        ),
      ),
    );
  }
}

class PinCreationFlow extends ConsumerStatefulWidget {
  const PinCreationFlow({
    super.key,
    required this.onSaved,
    this.changeOnly = false,
  });

  final PinSaveCallback onSaved;
  final bool changeOnly;

  @override
  ConsumerState<PinCreationFlow> createState() => _PinCreationFlowState();
}

class _PinCreationFlowState extends ConsumerState<PinCreationFlow> {
  int _step = 0;
  String? _firstPin;
  String? _error;
  bool _biometricAvailable = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (!widget.changeOnly) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final available = await ref.read(appLockPlatformProvider).isAvailable();
        if (mounted) setState(() => _biometricAvailable = available);
      });
    }
  }

  Future<bool> _first(String pin) async {
    if (isWeakPin(pin)) {
      setState(() => _error = "Pick a PIN that's harder to guess.");
      return false;
    }
    setState(() {
      _firstPin = pin;
      _error = null;
      _step = 1;
    });
    return true;
  }

  Future<bool> _confirm(String pin) async {
    if (pin != _firstPin) {
      setState(() {
        _firstPin = null;
        _error = "Those PINs don't match. Try again.";
        _step = 0;
      });
      return false;
    }
    if (widget.changeOnly || !_biometricAvailable) {
      await _save(false);
    } else {
      setState(() {
        _error = null;
        _step = 2;
      });
    }
    return true;
  }

  Future<void> _useBiometrics() async {
    if (_firstPin == null || _saving) return;
    setState(() => _saving = true);
    final ok = await ref
        .read(appLockProvider.notifier)
        .authenticateWithBiometrics();
    if (mounted) setState(() => _saving = false);
    await _save(ok);
  }

  Future<void> _save(bool bio) async {
    final pin = _firstPin;
    if (pin == null || _saving) return;
    setState(() => _saving = true);
    try {
      await widget.onSaved(pin, bio);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = "Couldn't save. Try again.";
          _step = 0;
          _firstPin = null;
        });
      }
    }
  }

  Future<bool> _handleBack() async {
    if (_step == 0) return true;
    setState(() {
      _step = 0;
      _firstPin = null;
      _error = null;
    });
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (_step) {
      0 => 'Create a PIN',
      1 => 'Enter it again',
      _ => 'Unlock with fingerprint or face?',
    };
    final body = switch (_step) {
      0 => "6 digits. You'll enter it each time you open Kuch Bhi.",
      1 => 'Type the same 6 digits.',
      _ => 'You can still use your PIN any time.',
    };

    return WillPopScope(
      onWillPop: _handleBack,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_step < 2)
            PinPad(
              key: ValueKey(_step),
              title: title,
              body: body,
              message: _error,
              enabled: !_saving,
              onCompleted: _step == 0 ? _first : _confirm,
            )
          else ...[
            Semantics(
              header: true,
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  height: 30 / 24,
                  fontWeight: FontWeight.w700,
                  color: context.t.ink,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: context.t.inkSoft),
            ),
            const SizedBox(height: 28),
            AppButton(
              expanded: true,
              busy: _saving,
              onPressed: _saving ? null : _useBiometrics,
              child: const Text('Use fingerprint or face'),
            ),
            AppButton(
              variant: AppButtonVariant.text,
              onPressed: _saving ? null : () => _save(false),
              child: const Text('Not now'),
            ),
          ],
        ],
      ),
    );
  }
}
