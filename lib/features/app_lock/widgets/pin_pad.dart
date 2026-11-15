
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/change_motion.dart';

class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.title,
    this.body,
    this.message,
    this.showFingerprint = false,
    this.onFingerprint,
    this.onCompleted,
    this.enabled = true,
    this.onChanged,
  });

  final String title;
  final String? body;
  final String? message;
  final bool showFingerprint;
  final VoidCallback? onFingerprint;
  final Future<bool> Function(String pin)? onCompleted;
  final bool enabled;
  final ValueChanged<String>? onChanged;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  final _digits = StringBuffer();
  int _wrong = 0; // E1: each wrong PIN shakes the dots once
  bool _busy = false;
  String? _spoken;

  // I2: a counting-down line is announced once, not every second.
  static String _shape(String? m) => m?.replaceAll(RegExp(r'\d'), '') ?? '';

  @override
  void initState() {
    super.initState();
    _spoken = widget.message;
  }

  @override
  void didUpdateWidget(PinPad old) {
    super.didUpdateWidget(old);
    if (_shape(widget.message) != _shape(_spoken)) _spoken = widget.message;
  }

  @override
  void dispose() {
    super.dispose();
  }

  String get _value => _digits.toString();

  void _clear() {
    if (_digits.isEmpty) return;
    setState(_digits.clear);
    widget.onChanged?.call(_value);
  }

  void _delete() {
    if (!widget.enabled || _busy || _digits.isEmpty) return;
    final value = _value;
    setState(() {
      _digits
        ..clear()
        ..write(value.substring(0, value.length - 1));
    });
    widget.onChanged?.call(_value);
  }

  Future<void> _digit(String digit) async {
    if (!widget.enabled || _busy || _digits.length >= 6) return;
    setState(() => _digits.write(digit));
    widget.onChanged?.call(_value);
    if (_digits.length != 6) return;
    // One check at a time: no retyping the 6th digit while one runs.
    _busy = true;
    final bool ok;
    try {
      ok = await widget.onCompleted?.call(_value) ?? false;
    } finally {
      _busy = false;
    }
    if (!mounted || ok) return;
    _clear();
    HapticFeedback.vibrate();
    setState(() => _wrong++);
  }

  Widget _key({
    String? digit,
    IconData? icon,
    String? label,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
    bool allowWhenDisabled = false,
  }) {
    final enabled =
        (widget.enabled || allowWhenDisabled) &&
        (onTap != null || digit != null);
    final VoidCallback? action = digit == null
        ? onTap
        : () {
            _digit(digit);
          };
    return Semantics(
      button: true,
      enabled: enabled,
      label: label ?? digit,
      child: GestureDetector(
        onLongPress: enabled ? onLongPress : null,
        child: SizedBox(
          width: 72,
          height: 72,
          child: Material(
            color: digit == null ? null : context.t.surface2,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: enabled ? action : null,
              child: icon == null
                  ? FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        digit ?? '',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                          color: enabled ? context.t.ink : context.t.inkFaint,
                        ),
                      ),
                    )
                  : Icon(icon, color: context.t.inkSoft, size: 22),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Focus(
          autofocus: true,
          child: Semantics(
            header: true,
            child: Text(
              widget.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                height: 30 / 24,
                fontWeight: FontWeight.w700,
                color: t.ink,
              ),
            ),
          ),
        ),
        if (widget.body != null) ...[
          const SizedBox(height: 6),
          Text(
            widget.body!,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, height: 22 / 15, color: t.inkSoft),
          ),
        ],
        const SizedBox(height: 12),
        Semantics(
          excludeSemantics: true,
          label: 'PIN, ${_digits.length} of 6 digits entered',
          child: ShakeOnChange(
            trigger: _wrong,
            child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 6; i++) ...[
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _digits.length ? t.ink : null,
                    border: Border.all(
                      color: i < _digits.length ? t.ink : t.line,
                      width: 2,
                    ),
                  ),
                ),
                if (i != 5) const SizedBox(width: 14),
              ],
            ],
          ),
          ),
        ),
        const SizedBox(height: 8),
        Semantics(
          liveRegion: true,
          label: _spoken,
          excludeSemantics: true,
          // Two lines reserved so the pad doesn't jump; grows at large text.
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: 36,
              minWidth: double.infinity,
            ),
            child: widget.message == null
                ? const SizedBox.shrink()
                : Text(
                    widget.message!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 18 / 13,
                      color: t.ink,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
            width: 72 * 3 + 16 * 2,
            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 16,
              children: [
                for (var i = 1; i <= 9; i++) _key(digit: '$i'),
                widget.showFingerprint
                    ? _key(
                        icon: Icons.fingerprint,
                        label: 'Unlock with fingerprint or face',
                        onTap: widget.onFingerprint,
                        allowWhenDisabled: true,
                      )
                    : ExcludeSemantics(child: _key()),
                _key(digit: '0'),
                _key(
                  icon: Icons.backspace_outlined,
                  label: 'Delete digit',
                  onTap: _delete,
                  onLongPress: _clear,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
