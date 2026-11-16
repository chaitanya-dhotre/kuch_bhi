import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// R13: the shared text-field decoration (page-4 pattern).
InputDecoration appFieldDecoration(
  BuildContext context, {
  String? label,
  String? hint,
  String? helper,
  String? prefixText,
}) {
  final t = context.t;
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(WarmPopTokens.radiusMd),
        borderSide: BorderSide(color: c, width: w),
      );
  return InputDecoration(
    labelText: label,
    hintText: hint,
    helperText: helper,
    prefixText: prefixText,
    labelStyle: TextStyle(fontSize: 13, color: t.inkSoft),
    hintStyle: TextStyle(fontSize: 15, color: t.inkFaint),
    helperStyle: TextStyle(fontSize: 13, height: 18 / 13, color: t.inkSoft),
    prefixStyle: TextStyle(fontSize: 15, color: t.inkSoft),
    counterStyle: TextStyle(fontSize: 13, height: 18 / 13, color: t.inkSoft),
    errorStyle: TextStyle(fontSize: 13, height: 18 / 13, color: t.ink),
    errorMaxLines: 2,
    prefixIconConstraints: const BoxConstraints(),
    enabledBorder: border(t.line),
    border: border(t.line),
    focusedBorder: border(t.accent, 1.5),
    errorBorder: border(t.error),
    focusedErrorBorder: border(t.error, 1.5),
    disabledBorder: border(t.line),
  );
}

/// R13 error line: ink 13/18 with a leading error icon (error-coloured text
/// fails contrast, foundation C4). Pass as `InputDecoration.error`; it is a
/// live region so the message is announced.
Widget appFieldError(BuildContext context, String message) {
  final t = context.t;
  return Semantics(
    liveRegion: true,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(Icons.error_outline, size: 16, color: t.error),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(message,
              style: TextStyle(fontSize: 13, height: 18 / 13, color: t.ink)),
        ),
      ],
    ),
  );
}
