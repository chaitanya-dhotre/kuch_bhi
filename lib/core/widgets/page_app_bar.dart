import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Registry R14: app-bar / dialog title style (20/26 w700 ink).
TextStyle pageTitleStyle(BuildContext context) => TextStyle(
      fontSize: 20,
      height: 26 / 20,
      fontWeight: FontWeight.w700,
      color: context.t.ink,
    );

/// Registry R14: app bar on the page colour, never a separate surface band
/// (the Page 4 Group Info bar; device finding 2026-10-29).
AppBar pageAppBar(
  BuildContext context,
  String title, {
  List<Widget>? actions,
}) {
  final t = context.t;
  return AppBar(
    backgroundColor: t.bg,
    surfaceTintColor: t.bg,
    elevation: 0,
    scrolledUnderElevation: 0,
    title: Semantics(
      header: true,
      child: Text(title, style: pageTitleStyle(context)),
    ),
    actions: actions,
  );
}
