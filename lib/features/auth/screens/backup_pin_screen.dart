import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/recovery_key.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../core/widgets/app_field.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/page_app_bar.dart';
import '../../../core/widgets/section_header.dart';
import '../../../data/local/database/app_database.dart';
import '../../../domain/repositories/message_repository.dart';
import '../../../infrastructure/offline/connectivity_signal.dart';
import '../../../infrastructure/repositories/message_repository_impl.dart';
import '../../../services/encryption_service.dart';
import '../../settings/widgets/font_choice_group.dart';
import '../../settings/widgets/notifications_status_row.dart';
import '../../settings/widgets/theme_mode_group.dart';
import '../providers/auth_provider.dart';
import '../providers/encryption_sync_provider.dart';
import '../widgets/auth_text_field.dart';
import '../widgets/auth_ui.dart';

enum BackupPinMode { setup, restore, change }

/// High-level restore steps. Drives the loading overlay message + icon so
/// the user gets continuous feedback during restore (which can take
/// 1–3 minutes re-paging the full encrypted history).
enum RestorePhase {
  idle,
  deriving, // Opening the key backup (PBKDF2 for a legacy PIN)
  finalisingKey, // Saving decrypted key to secure storage
  fetchingConvs, // Re-downloading the conversation list
  downloadingMsgs, // Paging through all messages across conversations
  decrypting, // AES-GCM decrypt of every message ciphertext
  ready, // All done, transitioning to home
}

extension _RestorePhaseCopy on RestorePhase {
  /// Human-readable message shown below the spinner.
  String get message {
    switch (this) {
      case RestorePhase.idle:
        return '';
      case RestorePhase.deriving:
        return 'Checking your key…';
      case RestorePhase.finalisingKey:
        return 'Unlocking your account…';
      case RestorePhase.fetchingConvs:
        return 'Loading your conversations…';
      case RestorePhase.downloadingMsgs:
        return 'Downloading messages…';
      case RestorePhase.decrypting:
        return 'Decrypting your messages…';
      case RestorePhase.ready:
        return 'Almost there…';
    }
  }
}

// E1 copy. Detail goes to debugPrint only, never into these.
const kMalformedKeyCopy =
    'A recovery key has 25 letters and numbers. Check that you have all of it.';
const kKeyMismatchCopy =
    'That\'s not the key on the last screen. Tap "Show the key again" and copy it.';
const kWrongSecretCopy =
    "That doesn't match your backup. Check for typos and try again.";
const kNoBackupCopy =
    'This account has no backup to restore. Tap "I lost it" to start fresh.';
const kUnsupportedBackupCopy =
    'This backup was made by a newer version of Kuch Bhi. Update the app, then try again.';

/// E1: what a failed save, restore or Start Fresh says.
String backupErrorCopy(
  Object error, {
  bool restoring = false,
  bool startingFresh = false,
}) {
  if (error is KeyMismatchException) {
    return "This phone's key isn't your account's current key, so your backup wasn't changed.";
  }
  if (startingFresh) {
    return "Couldn't start fresh. Check your connection and try again.";
  }
  if (isUnreachableError(error)) {
    return "Can't reach the server. Check your connection and try again.";
  }
  return restoring
      ? "Couldn't restore your messages. Try again."
      : "Couldn't save your backup. Try again.";
}

class BackupPinScreen extends ConsumerStatefulWidget {
  const BackupPinScreen({
    super.key,
    required this.mode,
    this.isOptionalSetup = false,
  });

  final BackupPinMode mode;
  final bool isOptionalSetup;

  @override
  ConsumerState<BackupPinScreen> createState() => _BackupPinScreenState();
}

/// entry = restore's field or change's intro; key → check wherever a
/// recovery key is made (setup, Start Fresh, change, upgrade).
enum _Step { entry, key, check }

class _BackupPinScreenState extends ConsumerState<BackupPinScreen> {
  late _Step _step = widget.mode == BackupPinMode.setup
      ? _Step.key
      : _Step.entry;

  /// C4: the canonical recovery key lives only here until it is saved:
  /// never logged, stored or routed. Leaving the screen drops it.
  late String? _recoveryKey = widget.mode == BackupPinMode.setup
      ? generateRecoveryKey()
      : null;
  bool _isStartingFresh = false;

  /// B2: a legacy PIN just unlocked the backup; the history sync waits.
  bool _upgrading = false;
  bool _isLoading = false;
  bool _savingBackup = false;
  bool _obscured = false;
  String? _fieldError;
  String? _cardError;

  // ── Progress (restore mode only) ──────────────────────────────
  // Drives the loading overlay's message and animated icon so the user has
  // continuous feedback instead of a static "Processing key derivation…"
  // string for the entire restore workflow.
  RestorePhase _restorePhase = RestorePhase.idle;
  int _convIndex = 0;
  int _convTotal = 0;
  int _msgCurrent = 0;
  int _msgTotal = 0;
  DateTime? _restoreStartedAt;

  final _restoreInput = TextEditingController();
  final _restoreFocus = FocusNode();
  final _checkInput = TextEditingController();
  final _checkFocus = FocusNode();
  final _usernameHint = TextEditingController();

  bool get _online => ref.read(isOnlineProvider).valueOrNull ?? true;
  bool get _matches =>
      _recoveryKey != null &&
      parseRecoveryKey(_checkInput.text) == _recoveryKey;

  @override
  void initState() {
    super.initState();
    if (widget.mode == BackupPinMode.restore) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _restoreFocus.requestFocus(),
      );
    }
  }

  @override
  void dispose() {
    _restoreInput.dispose();
    _restoreFocus.dispose();
    _checkInput.dispose();
    _checkFocus.dispose();
    _usernameHint.dispose();
    super.dispose();
  }

  /// Decision 11: a key is never shown twice; every visit makes a new one.
  void _newKey() => setState(() {
    _recoveryKey = generateRecoveryKey();
    _checkInput.clear();
    _fieldError = null;
    _cardError = null;
    _step = _Step.key;
  });

  void _toCheck() {
    final auth = ref.read(authProvider).valueOrNull;
    _usernameHint.text = auth is AuthAuthenticated ? auth.user.email : '';
    setState(() {
      _fieldError = null;
      _cardError = null;
      _step = _Step.check;
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _checkFocus.requestFocus(),
    );
  }

  /// Android side in MainActivity: a sensitive-flagged copy and a real clear.
  static const _clipboard = MethodChannel('kuch_bhi/clipboard');

  /// C7: flagged sensitive so keyboard clipboard histories (Gboard, Samsung)
  /// don't keep the key. Plain copy where the channel doesn't exist.
  Future<void> _copyKey() async {
    final text = formatRecoveryKey(_recoveryKey!);
    try {
      await _clipboard.invokeMethod('copySensitive', {'text': text});
    } on MissingPluginException {
      await Clipboard.setData(ClipboardData(text: text));
    }
    if (mounted) showToast(context, 'Recovery key copied.');
  }

  /// C7: a saved key shouldn't linger on the clipboard.
  /// shortcut: keyboard histories keep their own copy (device check
  /// 2026-10-31: Gboard keeps it masked as dots, Samsung Keyboard ignores the
  /// flag and shows it); no Android API deletes those entries.
  Future<void> _clearClipboard(String key) async {
    try {
      final clip = await Clipboard.getData(Clipboard.kTextPlain);
      if (parseRecoveryKey(clip?.text ?? '') != key) return;
      try {
        await _clipboard.invokeMethod('clear');
      } on MissingPluginException {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    } catch (e) {
      debugPrint('[Backup] clipboard clear failed: $e');
    }
  }

  void _onCheckChanged(String value) {
    final parsed = parseRecoveryKey(value);
    setState(() {
      _cardError = null;
      _fieldError = parsed != null && parsed != _recoveryKey
          ? kKeyMismatchCopy
          : null;
    });
  }

  Future<void> _save() async {
    final key = _recoveryKey;
    if (key == null || _isLoading || !_online) return;
    if (!_matches) {
      setState(() => _fieldError = kKeyMismatchCopy);
      _checkFocus.requestFocus();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _savingBackup = true;
      _cardError = null;
      _restoreStartedAt = DateTime.now();
    });

    final enc = ref.read(encryptionServiceProvider);
    try {
      if (_isStartingFresh) {
        // B8: the new key pair is made only now, after the key was checked.
        await enc.generateAndBackupNewKey(key);
      } else if (widget.mode == BackupPinMode.setup) {
        await enc.backupOrCreateKey(key);
      } else {
        // Change and upgrade re-wrap the device key; never a restore (B5).
        await enc.backupPrivateKey(key);
      }
    } catch (e) {
      debugPrint('[Backup] save failed: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _savingBackup = false;
          _cardError = backupErrorCopy(e, startingFresh: _isStartingFresh);
        });
      }
      return;
    }

    // backupOrCreateKey writes nothing when another phone backed up first;
    // then the router re-routes and nothing should claim a saved key.
    final saved = widget.mode != BackupPinMode.setup ||
        _isStartingFresh ||
        await enc.hasLocalPrivateKey();
    TextInput.finishAutofillContext(shouldSave: saved);
    if (saved) await _clearClipboard(key);
    ref.invalidate(showBackupBannerProvider);
    ref.invalidate(showBackupUpgradeBannerProvider);
    if (!mounted) return;
    if (_upgrading) {
      showToast(context, 'Recovery key saved.');
      return _restoreHistory();
    }
    if (widget.mode == BackupPinMode.change) {
      showToast(context, 'New recovery key saved.');
      context.pop();
      return;
    }
    ref.invalidate(encryptionSyncProvider);
    if (saved) showToast(context, 'Backup is on.');
    context.go(AppRoutes.home);
  }

  Future<void> _restore() async {
    if (_isLoading || !_online) return;
    final input = _restoreInput.text.trim();
    // C6: a legacy 6-digit PIN or a whole recovery key, checked before any
    // server call.
    if (!RegExp(r'^\d{6}$').hasMatch(input) &&
        parseRecoveryKey(input) == null) {
      setState(() => _fieldError = kMalformedKeyCopy);
      _restoreFocus.requestFocus();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _fieldError = null;
      _cardError = null;
      _restoreStartedAt = DateTime.now();
      _restorePhase = RestorePhase.deriving;
    });

    final RestoreResult result;
    try {
      result = await ref
          .read(encryptionServiceProvider)
          .restorePrivateKey(input);
    } catch (e) {
      debugPrint('[Restore] restore failed: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _restorePhase = RestorePhase.idle;
          _cardError = backupErrorCopy(e, restoring: true);
        });
      }
      return;
    }
    if (!mounted) return;
    if (result == RestoreResult.restored) return _restoreHistory();

    setState(() {
      _isLoading = false;
      _restorePhase = RestorePhase.idle;
    });
    switch (result) {
      case RestoreResult.restoredLegacy:
        // B2: the key is on the device; offer a recovery key before the sync.
        _upgrading = true;
        _restoreInput.clear(); // the PIN has done its job
        _newKey();
      case RestoreResult.wrongSecret:
        setState(() => _fieldError = kWrongSecretCopy);
        _restoreFocus.requestFocus();
      case RestoreResult.noBackup:
        setState(() => _cardError = kNoBackupCopy);
      case RestoreResult.unsupported:
        setState(() => _cardError = kUnsupportedBackupCopy);
      case RestoreResult.restored:
        break;
    }
  }

  /// The restore continuation: re-download + decrypt the full history now
  /// that the private key is restored (~1-3 min), then Home.
  Future<void> _restoreHistory() async {
    // `ref` dies with the screen; the sync and its router re-check do not.
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() {
      _isLoading = true;
      _savingBackup = false;
      _restorePhase = RestorePhase.finalisingKey;
    });
    try {
      setState(() => _restorePhase = RestorePhase.fetchingConvs);
      await ref
          .read(messageRepositoryProvider)
          .syncAllHistory(
            onProgress: (p) {
              // The sync outlives the screen if a redirect or back pops it.
              if (!mounted) return;
              switch (p.phase) {
                case HistorySyncPhase.fetchingConversations:
                  if (_restorePhase != RestorePhase.fetchingConvs) {
                    setState(() => _restorePhase = RestorePhase.fetchingConvs);
                  }
                  break;
                case HistorySyncPhase.downloadingMessages:
                  setState(() {
                    _restorePhase = RestorePhase.downloadingMsgs;
                    _convIndex = p.conversationIndex ?? _convIndex;
                    _convTotal = p.conversationCount ?? _convTotal;
                    _msgCurrent = p.messageCurrent ?? _msgCurrent;
                    _msgTotal = p.messageTotal ?? _msgTotal;
                    // Once we start downloading, the next phase is
                    // decrypting — flip to it for visual variety so the
                    // user sees movement.
                    if (_msgTotal > 0 &&
                        _msgCurrent / _msgTotal >= 0.2 &&
                        _restorePhase != RestorePhase.decrypting) {
                      _restorePhase = RestorePhase.decrypting;
                    }
                  });
                  break;
                case HistorySyncPhase.finalisingConversation:
                  // Keep showing "decrypting…" until all conversations done.
                  break;
                case HistorySyncPhase.complete:
                  setState(() => _restorePhase = RestorePhase.ready);
                  break;
              }
            },
          );
    } catch (e) {
      debugPrint('[Restore] history sync failed: $e');
    }
    container.invalidate(encryptionSyncProvider);
    if (mounted) {
      context.go(AppRoutes.home);
    }
  }

  Future<void> _skipBackup() async {
    final db = ref.read(appDatabaseProvider);
    await db.settingsDao.setSetting('pin_backup_skipped', 'true');
    await db.settingsDao.setSetting(
      'pin_backup_skipped_at',
      DateTime.now().toIso8601String(),
    );

    ref.invalidate(encryptionSyncProvider);
    if (mounted) {
      context.go(AppRoutes.home);
    }
  }

  Future<void> _lostIt() async {
    final ok = await showConfirmDialog(
      context: context,
      title: 'Start fresh?',
      body:
          "Without your recovery key, your old messages can't be opened.\n\n"
          'Starting fresh makes a new key. New messages work, but every older '
          'message stays locked for good.',
      confirmLabel: 'Start fresh',
      confirmIcon: Icons.warning_amber_rounded,
      destructive: true,
    );
    if (!ok || !mounted) return;
    _isStartingFresh = true;
    _newKey();
  }

  @override
  Widget build(BuildContext context) {
    final online = ref.watch(isOnlineProvider).valueOrNull ?? true;
    final change = widget.mode == BackupPinMode.change;
    final back = switch (_step) {
      _Step.check => _Step.key,
      _Step.key when _isStartingFresh => _Step.entry,
      _ => null,
    };

    final children = switch (_step) {
      _Step.entry when change => _changeIntro(),
      _Step.entry => _restoreForm(online),
      _Step.key => _keyStep(),
      _Step.check => _checkStep(online),
    };

    return Stack(
      children: [
        PopScope(
          canPop: back == null && !_upgrading,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (back == null) {
              // Upgrade key step: leaving would skip the history sync.
              if (!_isLoading) _restoreHistory();
              return;
            }
            setState(() {
              _step = back;
              _fieldError = null;
              _cardError = null;
              if (back == _Step.entry) {
                _isStartingFresh = false;
                _recoveryKey = null;
              }
            });
          },
          child: Scaffold(
            appBar: change ? pageAppBar(context, 'Recovery key') : null,
            body: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    kAuthGutter,
                    8,
                    kAuthGutter,
                    24,
                  ),
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: children,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // The restore view is a second root Scaffold, so a toast shows in
        // both; without heroes off, leaving for Home asserts.
        if (_isLoading)
          HeroMode(
            enabled: false,
            child: _RestoreOverlay(
              key: ValueKey(_savingBackup),
              isRestore: widget.mode == BackupPinMode.restore && !_savingBackup,
              phase: _restorePhase,
              startedAt: _restoreStartedAt,
              convIndex: _convIndex,
              convTotal: _convTotal,
              msgCurrent: _msgCurrent,
              msgTotal: _msgTotal,
            ),
          ),
      ],
    );
  }

  List<Widget> _header(
    String title,
    String body, {
    IconData icon = Icons.key_rounded,
  }) {
    final change = widget.mode == BackupPinMode.change;
    final align = change ? TextAlign.start : TextAlign.center;
    final t = context.t;
    return [
      if (!change) ...[
        Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: t.accent,
              borderRadius: BorderRadius.circular(WarmPopTokens.radiusMd),
            ),
            child: Icon(icon, color: t.onAccent, size: 28),
          ),
        ),
        const SizedBox(height: 12),
      ],
      AuthTitle(title, align: align),
      const SizedBox(height: 8),
      Text(body, textAlign: align, style: authBodyStyle(context)),
      const SizedBox(height: 16),
    ];
  }

  Widget _textAction(String label, VoidCallback onPressed) => Center(
    child: AppButton(
      variant: AppButtonVariant.text,
      onPressed: _isLoading ? null : onPressed,
      child: Text(label),
    ),
  );

  Widget _primary(
    String label,
    VoidCallback? onPressed, {
    bool needsNetwork = false,
    bool online = true,
  }) => OfflineDim(
    online: !needsNetwork || online,
    child: AppButton(
      expanded: true,
      onPressed: _isLoading || (needsNetwork && !online) ? null : onPressed,
      child: Text(label),
    ),
  );

  List<Widget> _changeIntro() => [
    const SizedBox(height: 8),
    Text(
      'Make a new recovery key for your backup. Your old key or PIN '
      'stops working once the new one is saved.',
      style: authBodyStyle(context),
    ),
    const SizedBox(height: 16),
    _primary('Make a new key', _newKey),
  ];

  List<Widget> _restoreForm(bool online) => [
    ..._header(
      'Restore your messages',
      'Enter the recovery key you saved. If you set a 6-digit PIN '
          'before, enter that instead.',
      icon: Icons.lock_outline,
    ),
    AuthTextField(
      controller: _restoreInput,
      focusNode: _restoreFocus,
      label: 'Recovery key or PIN',
      keyField: true,
      obscureText: _obscured,
      textCapitalization: TextCapitalization.characters,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.password],
      errorText: _fieldError,
      suffixIcon: PasswordToggle(
        obscured: _obscured,
        noun: 'key',
        onPressed: () => setState(() => _obscured = !_obscured),
      ),
      onChanged: (_) => setState(() {
        _fieldError = null;
        _cardError = null;
      }),
      onEditingComplete: _restore,
    ),
    if (_cardError != null) _ErrorCard(_cardError!),
    const SizedBox(height: 16),
    _primary(
      'Restore',
      _restoreInput.text.trim().isEmpty ? null : _restore,
      needsNetwork: true,
      online: online,
    ),
    if (!online) const OfflineActionHint(),
    const SizedBox(height: 8),
    _textAction('I lost it', _lostIt),
  ];

  List<Widget> _keyStep() {
    final change = widget.mode == BackupPinMode.change;
    final title = _upgrading
        ? 'Make your backup stronger'
        : _isStartingFresh
        ? 'Start fresh: save your new recovery key'
        : change
        ? 'Your new recovery key'
        : 'Save your recovery key';
    final body = _upgrading
        ? "You're in. Your backup still uses a 6-digit PIN, which is easy to "
              'crack. Save this recovery key to replace it.'
        : _isStartingFresh
        ? 'This makes a new key for your messages. Save this recovery key '
              'to protect it.'
        : 'Your messages are locked with a key that lives on this phone. '
              'This recovery key unlocks a copy of it on our server, so you '
              'can get your messages back after a reinstall. Nobody else has '
              'it, and nobody can reset it.';
    final t = context.t;
    return [
      if (widget.isOptionalSetup && widget.mode == BackupPinMode.setup) ...[
        Text(
          'Set up a recovery key to protect your messages.',
          textAlign: TextAlign.center,
          style: authBodyStyle(
            context,
          ).copyWith(color: t.ink, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
      ],
      ..._header(title, body),
      _KeyBlock(_recoveryKey!),
      const SizedBox(height: 10),
      AppButton(
        variant: AppButtonVariant.secondary,
        expanded: true,
        onPressed: _copyKey,
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.copy_rounded, size: 18),
            SizedBox(width: 8),
            Flexible(child: Text('Copy')),
          ],
        ),
      ),
      const SizedBox(height: 6),
      Text(
        "Save it in your password manager or write it down. Don't keep it "
        'only on this phone.',
        style: TextStyle(fontSize: 13, height: 18 / 13, color: t.inkSoft),
      ),
      const SizedBox(height: 14),
      _primary("I've saved it", _toCheck),
      if (widget.mode == BackupPinMode.setup)
        _textAction('Skip for now', _skipBackup),
      if (_upgrading) _textAction('Not now', _restoreHistory),
    ];
  }

  List<Widget> _checkStep(bool online) => [
    ..._header(
      'Check your recovery key',
      'Type or paste the key you just saved. This makes sure you can get '
          'back in later.',
    ),
    // D3: the account the key belongs to, so a password manager saves it
    // under the right name. Never shown or focused.
    Offstage(
      child: ExcludeSemantics(
        child: ExcludeFocus(
          child: TextField(
            controller: _usernameHint,
            autofillHints: const [AutofillHints.username],
          ),
        ),
      ),
    ),
    AuthTextField(
      controller: _checkInput,
      focusNode: _checkFocus,
      label: 'Recovery key',
      keyField: true,
      textCapitalization: TextCapitalization.characters,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.newPassword],
      errorText: _fieldError,
      onChanged: _onCheckChanged,
      onEditingComplete: _save,
    ),
    if (_cardError != null) _ErrorCard(_cardError!),
    const SizedBox(height: 16),
    _primary(
      'Turn on backup',
      _matches ? _save : null,
      needsNetwork: true,
      online: online,
    ),
    if (!online) const OfflineActionHint(),
    const SizedBox(height: 8),
    _textAction(
      'Show the key again',
      () => setState(() {
        _fieldError = null;
        _cardError = null;
        _step = _Step.key;
      }),
    ),
    if (_upgrading) _textAction('Not now', _restoreHistory),
  ];
}

/// C1 / G2: the key in groups of 5 that wrap whole, read out by TalkBack
/// one character at a time.
class _KeyBlock extends StatelessWidget {
  const _KeyBlock(this.recoveryKey);
  final String recoveryKey;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final groups = recoveryKeyGroups(recoveryKey);
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: groups.map((g) => g.split('').join(', ')).join(', then '),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(WarmPopTokens.radiusMd),
          border: Border.all(color: t.line),
        ),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 2,
          children: [
            for (final g in groups)
              Text(
                g,
                softWrap: false,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 19,
                  height: 30 / 19,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.1,
                  color: t.ink,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// E4: a save / restore failure, ink text with an error icon, announced once.
class _ErrorCard extends StatelessWidget {
  const _ErrorCard(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(WarmPopTokens.radiusMd),
          border: Border.all(color: t.line),
        ),
        child: appFieldError(context, message),
      ),
    );
  }
}

/// Full-screen modal shown during PIN restore. Replaces the previous
/// single-line "Processing key derivation…" string with a state-driven
/// progress display: per-step icon, friendly label, animated progress
/// dots, and an elapsed-time ticker. Hovered backdrop so the form is
/// clearly disabled.
class _RestoreOverlay extends StatefulWidget {
  const _RestoreOverlay({
    super.key,
    required this.isRestore,
    required this.phase,
    required this.startedAt,
    required this.convIndex,
    required this.convTotal,
    required this.msgCurrent,
    required this.msgTotal,
  });

  /// J1: restore gets the progress view; saving a backup (setup, change,
  /// upgrade, Start Fresh) gets the saving card below.
  final bool isRestore;
  final RestorePhase phase;
  final DateTime? startedAt;
  final int convIndex;
  final int convTotal;
  final int msgCurrent;
  final int msgTotal;

  @override
  State<_RestoreOverlay> createState() => _RestoreOverlayState();
}

class _RestoreOverlayState extends State<_RestoreOverlay>
    with SingleTickerProviderStateMixin {
  late final Stopwatch _stopwatch;
  late final AnimationController _pulseCtrl;

  late final bool _isRestore = widget.isRestore;

  /// J6: the count line is announced at most once per 10% step.
  int _announcedStep = -1;
  String _announced = '';

  @override
  void initState() {
    super.initState();
    _stopwatch = Stopwatch()..start();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    if (_isRestore) return;
    // Tick the elapsed-time display every second.
    _tick();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isRestore) return;
    // G5: reduced motion parks the saving card's pulse at full strength.
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulseCtrl.value = 1;
    } else if (!_pulseCtrl.isAnimating) {
      _pulseCtrl.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _stopwatch.stop();
    _ticker?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Timer? _ticker;
  void _tick() => _ticker =
      Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));

  String _formatElapsed() {
    final s = _stopwatch.elapsed.inSeconds;
    if (s < 60) return '${s}s';
    final m = s ~/ 60;
    final r = s % 60;
    return '${m}m ${r.toString().padLeft(2, '0')}s';
  }

  IconData _iconFor(RestorePhase phase) {
    switch (phase) {
      case RestorePhase.deriving:
        return Icons.key_outlined;
      case RestorePhase.finalisingKey:
        return Icons.lock_open_outlined;
      case RestorePhase.fetchingConvs:
        return Icons.chat_bubble_outline;
      case RestorePhase.downloadingMsgs:
        return Icons.cloud_download_outlined;
      case RestorePhase.decrypting:
        return Icons.lock_reset_outlined;
      case RestorePhase.ready:
        return Icons.check_circle_outline;
      case RestorePhase.idle:
        return Icons.hourglass_empty;
    }
  }

  /// Chats fraction once a total is known (the bar follows chats, S13).
  double? get _fraction => widget.convTotal > 0
      ? (widget.convIndex / widget.convTotal).clamp(0.0, 1.0)
      : null;

  String _countLine() {
    final n = NumberFormat.decimalPattern('en');
    return [
      if (widget.convTotal > 0)
        '${n.format(widget.convIndex)} of ${n.format(widget.convTotal)} chats',
      if (widget.msgTotal > 0)
        '${n.format(widget.msgCurrent)} of ${n.format(widget.msgTotal)} '
            'messages',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) =>
      _isRestore ? _buildRestore(context) : _buildSaving(context);

  /// J2–J6: progress card + While you wait (theme, font, notifications).
  /// Nothing here navigates, blocks or steals focus; the restore leaves only
  /// through its own frozen go(home).
  Widget _buildRestore(BuildContext context) {
    final t = context.t;
    final ready = widget.phase == RestorePhase.ready;
    final phase = widget.phase == RestorePhase.idle
        ? RestorePhase.deriving
        : widget.phase;
    final fraction = ready ? 1.0 : _fraction;
    final count = _countLine();
    // One chat (or none yet): step on messages, else the line never moves.
    final stepFraction = widget.convTotal > 1 || widget.msgTotal == 0
        ? (fraction ?? 0)
        : widget.msgCurrent / widget.msgTotal;
    final step = (stepFraction * 10).floor();
    if (step != _announcedStep || _announced.isEmpty) {
      _announcedStep = step;
      _announced = count;
    }
    final small = TextStyle(fontSize: 13, height: 18 / 13, color: t.inkSoft);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(WarmPopTokens.radiusMd),
                  border: Border.all(color: t.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Row(
                        children: [
                          if (ready) ...[
                            Icon(Icons.check_circle, size: 18, color: t.success),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(
                              ready
                                  ? 'Your chats are ready'
                                  : 'Unlocking your chats',
                              style: TextStyle(
                                fontSize: 16,
                                height: 22 / 16,
                                fontWeight: FontWeight.w600,
                                color: t.ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!ready) ...[
                      const SizedBox(height: 4),
                      Text(phase.message, style: small),
                    ],
                    const SizedBox(height: 12),
                    // J6: no total yet = "In progress". A progress bar's own
                    // semantics value must be numeric, so the parked 30%
                    // segment is excluded rather than announced as 30%.
                    Semantics(
                      label: 'Restore progress',
                      value: fraction == null ? 'In progress' : null,
                      child: ExcludeSemantics(
                        excluding: fraction == null,
                        child: ClipRRect(
                          borderRadius:
                              BorderRadius.circular(WarmPopTokens.radiusSm),
                          child: LinearProgressIndicator(
                            minHeight: 6,
                            // J6: reduced motion parks the indeterminate bar.
                            value: fraction ?? (reduceMotion ? .3 : null),
                            semanticsLabel: 'Restore progress',
                            semanticsValue: fraction == null
                                ? null
                                : '${(fraction * 100).round()}%',
                            backgroundColor: t.surface2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(t.accent),
                          ),
                        ),
                      ),
                    ),
                    if (count.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Semantics(
                        liveRegion: true,
                        label: _announced,
                        child: ExcludeSemantics(
                          child: Text(
                            count,
                            style: small.copyWith(
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ]),
                          ),
                        ),
                      ),
                    ],
                    if (!ready) ...[
                      const SizedBox(height: 8),
                      Text('Keep the app open. This takes a minute or two.',
                          style: small),
                    ],
                  ],
                ),
              ),
              const SectionHeader('While you wait'),
              const ThemeModeGroup(),
              const SectionHeader('Font'),
              const FontChoiceGroup(),
              const SizedBox(height: 12),
              const NotificationsStatusRow(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSaving(BuildContext context) {
    // Saving doesn't drive [_restorePhase]: one message, still alive.
    final phase = widget.phase == RestorePhase.idle
        ? RestorePhase.deriving
        : widget.phase;

    return Stack(
      children: [
        // Restore overlay stays a warm-dark modal in both themes so the
        // progress text keeps contrast: static tokens, never theme-flipped.
        const Opacity(
          opacity: 0.55,
          child: ModalBarrier(dismissible: false, color: WarmPopTokens.ink),
        ),
        Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.symmetric(
                horizontal: 24, vertical: 28),
            decoration: BoxDecoration(
              color: WarmPopTokens.ink,
              borderRadius: BorderRadius.circular(WarmPopTokens.radiusLg),
              boxShadow: const [
                BoxShadow(
                  color: WarmPopTokens.shadowDark,
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Pulsing icon — gives a feeling of continuous work even
                // when the underlying progress has lulls (e.g. between
                // PB pages).
                FadeTransition(
                  opacity: Tween<double>(begin: 0.4, end: 1.0).animate(
                    CurvedAnimation(
                      parent: _pulseCtrl,
                      curve: Curves.easeInOut,
                    ),
                  ),
                  child: Icon(
                    _iconFor(phase),
                    color: WarmPopTokens.accent,
                    size: 44,
                  ),
                ),
                const SizedBox(height: 18),
                // Phase message — keying on phase drives a soft swap
                // animation every time the underlying state changes.
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder: (child, anim) =>
                      FadeTransition(opacity: anim, child: child),
                  child: Text(
                    'Locking your backup…',
                    key: ValueKey(phase),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: WarmPopTokens.surface,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                LinearProgressIndicator(
                  // G5: parked like the restore bar under reduced motion.
                  value: MediaQuery.disableAnimationsOf(context) ? .3 : null,
                  minHeight: 4,
                  backgroundColor: WarmPopTokens.lineDark,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                      WarmPopTokens.accent),
                ),
                const SizedBox(height: 12),
                Text(
                  'Elapsed ${_formatElapsed()}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: WarmPopTokens.inkSoftDark,
                    fontSize: 12,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
