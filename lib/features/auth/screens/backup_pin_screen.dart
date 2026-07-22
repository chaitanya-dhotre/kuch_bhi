import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../../data/local/database/app_database.dart';
import '../../../infrastructure/repositories/message_repository_impl.dart';
import '../../../services/encryption_service.dart';
import '../providers/encryption_sync_provider.dart';

enum BackupPinMode { setup, restore, change }

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
    });

    final pin = _getPin();

    try {
      final enc = ref.read(encryptionServiceProvider);
      if (_currentMode == BackupPinMode.change) {
        final success = await enc.restorePrivateKey(pin);
        if (success) {
          setState(() {
            _isLoading = false;
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
          await enc.backupPrivateKey(pin);
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
        final success = await enc.restorePrivateKey(pin);
        if (success) {
          // Reinstall recovery: re-download + decrypt the full history now
          // that the private key is restored.
          try {
            await ref.read(messageRepositoryProvider).syncAllHistory();
          } catch (e) {
            debugPrint('[Restore] history sync failed: $e');
          }
          ref.invalidate(encryptionSyncProvider);
          if (mounted) {
            context.go(AppRoutes.home);
          }
        } else {
          setState(() {
            _isLoading = false;
            _errorMessage = "Incorrect PIN. Try again.";
          });
          for (final c in _pinControllers) {
            c.clear();
          }
          _pinFocusNodes[0].requestFocus();
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
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
              child: const Text(
                'Start Fresh',
                style: TextStyle(color: Colors.red),
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
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.lock_person_outlined,
                          color: Colors.white,
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
                              color: AppColors.primary,
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
                        style: const TextStyle(
                          color: AppColors.error,
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
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
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
        if (_isLoading)
          const Stack(
            children: [
              Opacity(
                opacity: 0.4,
                child: ModalBarrier(dismissible: false, color: Colors.black),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      'Processing key derivation...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }
}
