import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Registry R19: the ONLY way to open a bottom sheet (grep-gated). The
/// shape comes from `bottomSheetTheme` (radiusLg, no tint).
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool useRootNavigator = false,
  Duration? exit,
}) {
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    backgroundColor: context.t.surface,
    barrierColor: WarmPopTokens.scrim,
    // Motion B4; L7: under reduced motion no slide, a 150 ms fade instead.
    sheetAnimationStyle: sheetMotion(context, exit: exit),
    builder: MediaQuery.disableAnimationsOf(context)
        ? (ctx) => TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: WarmPopTokens.motionFast,
            builder: (_, o, child) => FadeTransition(
              opacity: AlwaysStoppedAnimation(o),
              child: child,
            ),
            child: builder(ctx),
          )
        : builder,
  );
}

/// Motion B4: enter [WarmPopTokens.motionBase] on curveEnter, exit 190 ms
/// on curveExit. Reduced motion: no slide (decision 8); the sheet's
/// content fades in over 150 ms instead (L7).
AnimationStyle sheetMotion(BuildContext context, {Duration? exit}) =>
    MediaQuery.disableAnimationsOf(context)
    ? AnimationStyle.noAnimation
    : AnimationStyle(
        duration: WarmPopTokens.motionBase,
        reverseDuration: exit ?? WarmPopTokens.motionExit,
        curve: WarmPopTokens.curveEnter,
        // Flipped: the exit accelerates away in real time (L3).
        reverseCurve: WarmPopTokens.curveExit.flipped,
      );

/// Registry R19: handle, optional title (+ action), optional header, then
/// the body. Pass [children] (the chrome scrolls them) or [body] (a
/// Flexible that scrolls itself and owns its padding; handle and title stay
/// put). Max height = 90% of (screen − keyboard); the keyboard lifts it.
class AppSheetChrome extends StatelessWidget {
  const AppSheetChrome({
    super.key,
    this.handleKey,
    this.title,
    this.titleAction,
    this.header,
    this.children,
    this.body,
  }) : assert((children == null) != (body == null),
            'pass children or body, not both');

  final Key? handleKey;
  final String? title;
  final Widget? titleAction;

  /// The preview row; a 1px divider separates it from the rows.
  final Widget? header;
  final List<Widget>? children;
  final Widget? body;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final mq = MediaQuery.of(context);
    final inset = mq.viewInsets.bottom;
    final maxHeight = math.max(0.0, (mq.size.height - inset) * 0.9);

    final top = <Widget>[
      ExcludeSemantics(
        child: Center(
          child: Container(
            key: handleKey,
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(top: 8, bottom: 12),
            decoration: BoxDecoration(
              color: t.line,
              borderRadius: BorderRadius.circular(WarmPopTokens.radiusPill),
            ),
          ),
        ),
      ),
      if (title != null)
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  title!,
                  style: TextStyle(
                    fontSize: 20,
                    height: 26 / 20,
                    fontWeight: FontWeight.w700,
                    color: t.ink,
                  ),
                ),
              ),
            ),
            if (titleAction != null) ...[
              const SizedBox(width: 12),
              titleAction!,
            ],
          ],
        ),
      if (header != null) ...[
        header!,
        const SizedBox(height: 8),
        Divider(height: 1, thickness: 1, color: t.line),
      ],
      if (title != null || header != null) const SizedBox(height: 8),
    ];

    final Widget content = body != null
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: top,
                ),
              ),
              Flexible(child: body!),
            ],
          )
        : SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [...top, ...children!],
            ),
          );

    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: content,
        ),
      ),
    );
  }
}

/// Registry R19: one sheet row, still a [ListTile] (tests read its
/// `trailing`). [trailing] is a value (13/18 inkSoft, end-aligned, wraps);
/// on a disabled row it is the offline hint and is NOT dimmed, while icon +
/// label share one 38% dim. [destructive] = error icon + ink label (C4b).
/// [key] lands on the [ListTile] itself, so tests that read the tile by key
/// keep working.
class SheetActionRow extends StatelessWidget {
  // The key goes to the ListTile, not this wrapper (see above).
  // ignore: use_key_in_widget_constructors
  const SheetActionRow({
    Key? key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.trailing,
    this.enabled = true,
    this.destructive = false,
    this.semanticsLabel,
  }) : tileKey = key;

  final Key? tileKey;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? subtitle;
  final String? trailing;
  final bool enabled;
  final bool destructive;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final caption = TextStyle(fontSize: 13, height: 18 / 13, color: t.inkSoft);
    final iconWidget =
        Icon(icon, size: 24, color: destructive ? t.error : t.inkSoft);
    final labelText = Text(
      label,
      style: TextStyle(
        fontSize: 15,
        height: 22 / 15,
        fontWeight: FontWeight.w600,
        color: t.ink,
      ),
    );
    final subtitleText =
        subtitle == null ? null : Text(subtitle!, style: caption);

    final Widget? leading;
    final Widget title;
    final Widget? trailingWidget;
    if (!enabled) {
      leading = null;
      title = Opacity(
        opacity: 0.38,
        child: Row(
          children: [
            iconWidget,
            const SizedBox(width: 16),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [labelText, ?subtitleText],
              ),
            ),
          ],
        ),
      );
      // longestLine: a wrapped hint must not claim the whole tile width
      // (ListTile asserts on that at 200% text).
      trailingWidget = trailing == null
          ? null
          : Text(
              trailing!,
              style: caption,
              textWidthBasis: TextWidthBasis.longestLine,
            );
    } else {
      leading = iconWidget;
      title = trailing == null
          ? labelText
          : Row(
              children: [
                Expanded(child: labelText),
                const SizedBox(width: 12),
                Flexible(
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Text(
                      trailing!,
                      style: caption,
                      textAlign: TextAlign.end,
                    ),
                  ),
                ),
              ],
            );
      trailingWidget = null;
    }

    final tile = ListTile(
      key: tileKey,
      leading: leading,
      title: title,
      subtitle: enabled ? subtitleText : null,
      trailing: trailingWidget,
      onTap: enabled ? onTap : null,
      enabled: enabled,
      minTileHeight: 52,
      contentPadding: EdgeInsets.zero,
    );
    if (semanticsLabel == null) return tile;
    return Semantics(
      label: semanticsLabel,
      button: true,
      enabled: enabled,
      child: tile,
    );
  }
}
