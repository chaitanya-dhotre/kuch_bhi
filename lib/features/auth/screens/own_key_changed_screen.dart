import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../core/widgets/app_toast.dart';
import '../../security/own_key_actions.dart';

/// Key-change-warning spec E1: the server holds a different key for me than
/// this phone does. Never acted on silently; the user keeps this phone's
/// key (re-published) or removes it and restores with the recovery key.
class OwnKeyChangedScreen extends ConsumerStatefulWidget {
  const OwnKeyChangedScreen({super.key});

  @override
  ConsumerState<OwnKeyChangedScreen> createState() =>
      _OwnKeyChangedScreenState();
}

class _OwnKeyChangedScreenState extends ConsumerState<OwnKeyChangedScreen> {
  var _busy = false;

  Future<void> _keep() async {
    setState(() => _busy = true);
    try {
      await keepOwnKey(ref);
    } catch (_) {
      if (mounted) {
        showToast(
          context,
          "Couldn't reach the server. Check your connection and try again.",
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final ok = await showConfirmDialog(
      context: context,
      title: 'Use the new code?',
      body:
          "This phone's key will be removed. Messages only open again after "
          'you restore with your recovery key.',
      confirmLabel: 'Continue',
    );
    if (!ok || !mounted) return;
    await dropOwnKeyForRestore(ref);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: t.surface2,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.shield_outlined,
                      size: 32,
                      color: t.accentText,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Semantics(
                  header: true,
                  child: Text(
                    'Your security code changed',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      height: 30 / 24,
                      fontWeight: FontWeight.w700,
                      color: t.ink,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  "Your account has a new code that this phone didn't make. "
                  'If you started fresh on another phone, restore here with '
                  "your new recovery key. If you didn't, keep this phone's "
                  'code; your friends will see it change back.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    height: 22 / 15,
                    color: t.inkSoft,
                  ),
                ),
                const SizedBox(height: 20),
                AppButton(
                  key: const ValueKey('own-key-keep'),
                  expanded: true,
                  busy: _busy,
                  onPressed: _keep,
                  child: const Text("Keep this phone's code"),
                ),
                const SizedBox(height: 8),
                AppButton(
                  key: const ValueKey('own-key-restore'),
                  variant: AppButtonVariant.secondary,
                  expanded: true,
                  onPressed: _busy ? null : _restore,
                  child: const Text('Restore with recovery key'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
