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
///
/// `leading` / `bottom` are pass-throughs for the two shapes that don't fit
/// the plain bar: a page with its own back affordance (New Group step 2) and
/// a page with a `TabBar` (Media & Docs).
AppBar pageAppBar(
  BuildContext context,
  String title, {
  List<Widget>? actions,
  Widget? leading,
  PreferredSizeWidget? bottom,
}) {
  final t = context.t;
  return AppBar(
    backgroundColor: t.bg,
    surfaceTintColor: t.bg,
    elevation: 0,
    scrolledUnderElevation: 0,
    leading: leading,
    bottom: bottom,
    title: Semantics(
      header: true,
      child: Text(title, style: pageTitleStyle(context)),
    ),
    actions: actions,
  );
}
