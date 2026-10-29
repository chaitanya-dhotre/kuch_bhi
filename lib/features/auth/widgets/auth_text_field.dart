import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_field.dart';

/// The auth screens' field: focus/action/validator wiring on the R13
/// decoration. Validator and server ([errorText]) errors render through
/// `appFieldError` (icon + ink text, live region), never error-red text.
class AuthTextField extends StatelessWidget {
  const AuthTextField({
    super.key,
    required this.controller,
    required this.label,
    this.focusNode,
    this.keyboardType,
    this.textInputAction,
    this.readOnly = false,
    this.obscureText = false,
    this.suffixIcon,
    this.helperText,
    this.prefixText,
    this.errorText,
    this.autofillHints,
    this.textCapitalization = TextCapitalization.none,
    this.onChanged,
    this.onEditingComplete,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool readOnly;
  final bool obscureText;
  final Widget? suffixIcon;
  final String? helperText;
  final String? prefixText;

  /// A server error for this field (D4); wins over the validator's.
  final String? errorText;
  final Iterable<String>? autofillHints;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onEditingComplete;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return FormField<String>(
      validator: validator == null ? null : (_) => validator!(controller.text),
      builder: (field) {
        final error = errorText ?? field.errorText;
        return TextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          readOnly: readOnly,
          obscureText: obscureText,
          autocorrect: !obscureText && autofillHints == null,
          enableSuggestions: !obscureText,
          autofillHints: readOnly ? null : autofillHints,
          textCapitalization: textCapitalization,
          onEditingComplete: onEditingComplete,
          onChanged: (v) {
            field.didChange(v);
            onChanged?.call(v);
          },
          style: TextStyle(
              fontSize: 15,
              height: 22 / 15,
              color: readOnly ? t.inkSoft : t.ink),
          decoration: appFieldDecoration(
            context,
            label: label,
            helper: helperText,
            prefixText: prefixText,
          ).copyWith(
            suffixIcon: suffixIcon,
            error: error == null ? null : appFieldError(context, error),
          ),
        );
      },
    );
  }
}
