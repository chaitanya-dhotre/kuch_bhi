import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/section_header.dart';
import '../../../data/local/database/app_database.dart';
import '../../../domain/repositories/message_repository.dart';
import '../../../infrastructure/repositories/message_repository_impl.dart';
import '../../../services/encryption_service.dart';
import '../../settings/widgets/font_choice_group.dart';
import '../../settings/widgets/notifications_status_row.dart';
import '../../settings/widgets/theme_mode_group.dart';
import '../providers/encryption_sync_provider.dart';

enum BackupPinMode { setup, restore, change }

/// High-level restore steps. Drives the loading overlay message + icon so
/// the user gets continuous feedback during PIN restore (which can take
/// 1–3 minutes re-paging the full encrypted history).
enum RestorePhase {
  idle,
  deriving,         // PBKDF2 + AES-GCM decrypt of the encrypted private key
  finalisingKey,    // Saving decrypted key to secure storage
  fetchingConvs,    // Re-downloading the conversation list
  downloadingMsgs,  // Paging through all messages across conversations
  decrypting,       // AES-GCM decrypt of every message ciphertext
  ready,            // All done, transitioning to home
}

extension _RestorePhaseCopy on RestorePhase {
  /// Human-readable message shown below the spinner.
  String get message {
    switch (this) {
      case RestorePhase.idle:
        return '';
      case RestorePhase.deriving:
        return 'Deriving your encryption key…';
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

class _BackupPinScreenState extends ConsumerState<BackupPinScreen> {
  late BackupPinMode _currentMode;
  bool _isStartingFresh = false;
  bool _isLoading = false;
  bool _isValid = false;
  String? _errorMessage;

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

  final List<TextEditingController> _pinControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _pinFocusNodes = List.generate(6, (_) => FocusNode());

  final List<TextEditingController> _confirmControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _confirmFocusNodes = List.generate(6, (_) => FocusNode());

  @override
  void initState() {
    super.initState();
    _currentMode = widget.mode;

    // Attach key listener to focus nodes for empty backspace detection
    for (int i = 0; i < 6; i++) {
      _pinFocusNodes[i] = FocusNode(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.backspace) {
            if (_pinControllers[i].text.isEmpty && i > 0) {
              _pinControllers[i - 1].clear();
              _pinFocusNodes[i - 1].requestFocus();
              _validateInput();
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
      );

      _confirmFocusNodes[i] = FocusNode(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.backspace) {
            if (_confirmControllers[i].text.isEmpty && i > 0) {
              _confirmControllers[i - 1].clear();
              _confirmFocusNodes[i - 1].requestFocus();
              _validateInput();
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pinFocusNodes[0].requestFocus();
    });
  }

  @override
  void dispose() {
    for (final c in _pinControllers) {
      c.dispose();
    }
    for (final f in _pinFocusNodes) {
      f.dispose();
    }
    for (final c in _confirmControllers) {
      c.dispose();
    }
    for (final f in _confirmFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _validateInput() {
    setState(() {
      _errorMessage = null;
      final pin = _getPin();
      final isDigitsOnly = RegExp(r'^\d+$').hasMatch(pin);
      if (_currentMode == BackupPinMode.change) {
        _isValid = pin.length == 6 && isDigitsOnly;
      } else if (_currentMode == BackupPinMode.setup) {
        final confirmPin = _getConfirmPin();
        final isConfirmDigitsOnly = RegExp(r'^\d+$').hasMatch(confirmPin);
        _isValid = pin.length == 6 &&
            confirmPin.length == 6 &&
            pin == confirmPin &&
            isDigitsOnly &&
            isConfirmDigitsOnly;
      } else {
        _isValid = pin.length == 6 && isDigitsOnly;
      }
    });
  }

  String _getPin() => _pinControllers.map((c) => c.text).join();
  String _getConfirmPin() => _confirmControllers.map((c) => c.text).join();

  Future<void> _submit() async {
    if (!_isValid || _isLoading) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _restoreStartedAt = DateTime.now();
    });

    final pin = _getPin();

    try {
      final enc = ref.read(encryptionServiceProvider);
      if (_currentMode == BackupPinMode.change) {
        setState(() => _restorePhase = RestorePhase.deriving);
        final success = await enc.restorePrivateKey(pin);
        if (success) {
          setState(() {
            _isLoading = false;
            _restorePhase = RestorePhase.idle;
            _currentMode = BackupPinMode.setup;
            _isValid = false;
          });
          for (final c in _pinControllers) {
            c.clear();
          }
          for (final c in _confirmControllers) {
            c.clear();
          }
          _pinFocusNodes[0].requestFocus();
        } else {
          setState(() {
            _isLoading = false;
            _restorePhase = RestorePhase.idle;
            _errorMessage = "Incorrect current PIN. Try again.";
          });
          for (final c in _pinControllers) {
            c.clear();
          }
          _pinFocusNodes[0].requestFocus();
        }
      } else if (_currentMode == BackupPinMode.setup) {
        if (_isStartingFresh) {
          await enc.generateAndBackupNewKey(pin);
        } else {
          await enc.backupOrCreateKey(pin);
        }
        ref.invalidate(encryptionSyncProvider);
        ref.invalidate(showBackupBannerProvider);
        if (mounted) {
          if (widget.mode == BackupPinMode.change) {
            context.pop();
          } else {
            context.go(AppRoutes.home);
          }
        }
      } else {
        // ── Restore mode ──
        // Two long jobs back-to-back:
        //   1. EncryptionService.restorePrivateKey(pin) — PBKDF2 + AES-GCM
        //      (~5-10 s) then save to secure storage.
        //   2. MessageRepository.syncAllHistory() — page through every
        //      conversation's history and decrypt every message (~1-3 min).
        setState(() => _restorePhase = RestorePhase.deriving);
        final success = await enc.restorePrivateKey(pin);
        if (!success) {
          setState(() {
            _isLoading = false;
            _restorePhase = RestorePhase.idle;
            _errorMessage = "Incorrect PIN. Try again.";
          });
          for (final c in _pinControllers) {
            c.clear();
          }
          _pinFocusNodes[0].requestFocus();
          return;
        }
        setState(() => _restorePhase = RestorePhase.finalisingKey);

        // Reinstall recovery: re-download + decrypt the full history now
        // that the private key is restored.
        try {
          setState(() => _restorePhase = RestorePhase.fetchingConvs);
          await ref.read(messageRepositoryProvider).syncAllHistory(
            onProgress: (p) {
              switch (p.phase) {
                case HistorySyncPhase.fetchingConversations:
                  if (_restorePhase != RestorePhase.fetchingConvs) {
                    setState(() => _restorePhase =
                        RestorePhase.fetchingConvs);
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
        ref.invalidate(encryptionSyncProvider);
        if (mounted) {
          context.go(AppRoutes.home);
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _restorePhase = RestorePhase.idle;
        _errorMessage = "An error occurred: ${e.toString()}";
      });
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

  void _showForgotPinDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Start Fresh?'),
          content: const Text(
            'Without your PIN, your existing encrypted messages cannot be decrypted.\n\n'
            'If you choose to start fresh, a new key pair will be generated. '
            'You will be able to send and receive new messages, but all historical messages will be permanently undecryptable. '
            'To secure the new key, you will need to set a new PIN.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  _currentMode = BackupPinMode.setup;
                  _isStartingFresh = true;
                  for (final c in _pinControllers) {
                    c.clear();
                  }
                  for (final c in _confirmControllers) {
                    c.clear();
                  }
                  _validateInput();
                });
                _pinFocusNodes[0].requestFocus();
              },
              child: Text(
                'Start Fresh',
                style: TextStyle(color: context.t.error),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPinRow(
    List<TextEditingController> controllers,
    List<FocusNode> focusNodes,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(6, (index) {
        return SizedBox(
          width: 44,
          height: 52,
          child: TextFormField(
            controller: controllers[index],
            focusNode: focusNodes[index],
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0,
                ),
            maxLength: 1,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(1),
            ],
            decoration: InputDecoration(
              counterText: "",
              contentPadding: EdgeInsets.zero,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.15),
                  width: 1.5,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2.2,
                ),
              ),
            ),
            onChanged: (value) {
              if (value.isNotEmpty) {
                if (index < 5) {
                  focusNodes[index + 1].requestFocus();
                } else {
                  if (_currentMode == BackupPinMode.setup &&
                      controllers == _pinControllers) {
                    _confirmFocusNodes[0].requestFocus();
                  } else {
                    focusNodes[index].unfocus();
                  }
                }
              }
              _validateInput();
            },
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _currentMode == BackupPinMode.change
        ? "Change Backup PIN"
        : _currentMode == BackupPinMode.setup
            ? (_isStartingFresh ? "Start Fresh: New PIN" : "Create Backup PIN")
            : "Restore Encryption Key";

    final bodyText = _currentMode == BackupPinMode.change
        ? "Enter your current 6-digit backup PIN to verify it's you."
        : _currentMode == BackupPinMode.setup
            ? "This 6-digit PIN protects your encryption key. You'll need it if you reinstall the app. Store it safely."
            : "Enter your backup PIN to restore your encrypted messages. This is the PIN you set when you first registered.";

    final hasExplanatoryPrefix =
        widget.isOptionalSetup && _currentMode == BackupPinMode.setup;

    return Stack(
      children: [
        Scaffold(
          appBar: widget.mode == BackupPinMode.change
              ? AppBar(
                  title: const Text('Change PIN'),
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                )
              : null,
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 16),
                    // Logo Icon
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
                      title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 10),

                    if (hasExplanatoryPrefix) ...[
                      Text(
                        "Set up a backup PIN to protect your key.",
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: context.t.accent,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 6),
                    ],

                    Text(
                      bodyText,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.6),
                            height: 1.4,
                          ),
                    ),
                    const SizedBox(height: 36),

                    // PIN Entry Section
                    Card(
                      elevation: 0,
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.08),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 24,
                          horizontal: 16,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _currentMode == BackupPinMode.change
                                  ? "Enter Current PIN"
                                  : _currentMode == BackupPinMode.setup
                                      ? "Choose PIN"
                                      : "Enter PIN",
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.65),
                                  ),
                            ),
                            const SizedBox(height: 12),
                            _buildPinRow(_pinControllers, _pinFocusNodes),
                            if (_currentMode == BackupPinMode.setup) ...[
                              const SizedBox(height: 24),
                              Text(
                                "Confirm PIN",
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.65),
                                    ),
                              ),
                              const SizedBox(height: 12),
                              _buildPinRow(
                                _confirmControllers,
                                _confirmFocusNodes,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ).animate().fade(duration: 350.ms),

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

                    // Save/Restore Button
                    FilledButton(
                      onPressed: _isValid && !_isLoading ? _submit : null,
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
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: context.t.onAccent,
                              ),
                            )
                          : Text(
                              _currentMode == BackupPinMode.change
                                  ? "Verify PIN"
                                  : _currentMode == BackupPinMode.setup
                                      ? "Save PIN"
                                      : "Restore",
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),

                    const SizedBox(height: 20),

                    // Lower text actions
                    if (_currentMode == BackupPinMode.setup && widget.mode != BackupPinMode.change) ...[
                      Center(
                        child: TextButton(
                          onPressed: _isLoading ? null : _skipBackup,
                          child: Text(
                            "Skip for now",
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.4),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ] else if (_currentMode == BackupPinMode.restore) ...[
                      Center(
                        child: TextButton(
                          onPressed: _isLoading ? null : _showForgotPinDialog,
                          child: Text(
                            "I forgot my PIN",
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.4),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_isLoading) _RestoreOverlay(
          phase: _restorePhase,
          startedAt: _restoreStartedAt,
          convIndex: _convIndex,
          convTotal: _convTotal,
          msgCurrent: _msgCurrent,
          msgTotal: _msgTotal,
        ),
      ],
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
    required this.phase,
    required this.startedAt,
    required this.convIndex,
    required this.convTotal,
    required this.msgCurrent,
    required this.msgTotal,
  });

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

  /// J1: restore gets the progress view; PIN setup / change keep the
  /// saving card below unchanged.
  late final bool _isRestore;

  /// J6: the count line is announced at most once per 10% step.
  int _announcedStep = -1;
  String _announced = '';

  @override
  void initState() {
    super.initState();
    _isRestore = context.findAncestorWidgetOfExactType<BackupPinScreen>()
            ?.mode ==
        BackupPinMode.restore;
    _stopwatch = Stopwatch()..start();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    if (_isRestore) return;
    _pulseCtrl.repeat(reverse: true);
    // Tick the elapsed-time display every second.
    _tick();
  }

  @override
  void dispose() {
    _stopwatch.stop();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _tick() async {
    while (mounted) {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      setState(() {});
    }
  }

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

  /// Secondary detail line shown below the main message — tells the user
  /// where they are in the multi-conversation download / decrypt cycle.
  String? _detailFor(RestorePhase phase) {
    if (phase == RestorePhase.downloadingMsgs && widget.msgTotal > 0) {
      return 'Message ${widget.msgCurrent} of ${widget.msgTotal}'
          '${widget.convTotal > 1 ? " · chat ${widget.convIndex}/${widget.convTotal}" : ""}';
    }
    if (phase == RestorePhase.decrypting && widget.convTotal > 0) {
      return 'Chat ${widget.convIndex} of ${widget.convTotal}';
    }
    if (phase == RestorePhase.ready) {
      return 'Opening your chats…';
    }
    return null;
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
    // In setup/change PIN modes we don't drive [_restorePhase] — fall back
    // to a generic "Saving your PIN…" message that still feels alive.
    final phase = widget.phase == RestorePhase.idle
        ? RestorePhase.deriving
        : widget.phase;
    final detail = _detailFor(phase);

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
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: WarmPopTokens.ink.withValues(alpha: 0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
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
                    phase.message,
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
                if (detail != null) ...[
                  const SizedBox(height: 8),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Text(
                      detail,
                      key: ValueKey('${phase.name}-$detail'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: WarmPopTokens.surface.withValues(alpha: 0.6),
                        fontSize: 13,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                LinearProgressIndicator(
                  minHeight: 4,
                  backgroundColor: WarmPopTokens.surface.withValues(alpha: 0.1),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                      WarmPopTokens.accent),
                ),
                const SizedBox(height: 12),
                Text(
                  'Elapsed ${_formatElapsed()}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: WarmPopTokens.surface.withValues(alpha: 0.45),
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
