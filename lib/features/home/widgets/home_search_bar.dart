import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';

/// Always-visible Home search pill.
///
/// Search is deliberately owned by HomeScreen so filtering remains ephemeral
/// and can keep the list's scroll position. This widget only owns the pill's
/// focus/text affordances.
class HomeSearchBar extends StatefulWidget {
  const HomeSearchBar({
    super.key,
    required this.controller,
    required this.focusNode,
    this.onChanged,
    this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;

  @override
  State<HomeSearchBar> createState() => _HomeSearchBarState();
}

class _HomeSearchBarState extends State<HomeSearchBar> {
  late bool _hasText;
  late bool _hasFocus;

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.isNotEmpty;
    _hasFocus = widget.focusNode.hasFocus;
    widget.controller.addListener(_handleTextChanged);
    widget.focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant HomeSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_handleTextChanged);
      widget.controller.addListener(_handleTextChanged);
      _hasText = widget.controller.text.isNotEmpty;
    }
    if (!identical(oldWidget.focusNode, widget.focusNode)) {
      oldWidget.focusNode.removeListener(_handleFocusChanged);
      widget.focusNode.addListener(_handleFocusChanged);
      _hasFocus = widget.focusNode.hasFocus;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleTextChanged);
    widget.focusNode.removeListener(_handleFocusChanged);
    super.dispose();
  }

  void _handleTextChanged() {
    final hasText = widget.controller.text.isNotEmpty;
    if (hasText == _hasText || !mounted) return;
    setState(() => _hasText = hasText);
  }

  void _handleFocusChanged() {
    if (!mounted) return;
    final hasFocus = widget.focusNode.hasFocus;
    if (hasFocus == _hasFocus) return;
    setState(() => _hasFocus = hasFocus);
  }

  void _clear() {
    widget.controller.clear();
    widget.onChanged?.call('');
    widget.onClear?.call();
    widget.focusNode.requestFocus();
  }

  void _requestFocus() {
    // The closed pill does not contain the TextField yet, so its FocusNode is
    // unattached on the first tap. Reveal the field first, then focus it once
    // the new element is mounted.
    if (!_hasFocus) setState(() => _hasFocus = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.focusNode.requestFocus();
    });
  }

  Widget _buildField(BuildContext context, ColorTokens t) {
    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      onChanged: widget.onChanged,
      cursorColor: t.accent,
      textInputAction: TextInputAction.search,
      textAlignVertical: TextAlignVertical.center,
      style: TextStyle(fontSize: 13, height: 18 / 13, color: t.ink),
      decoration: InputDecoration(
        hintText: 'Search chats',
        hintStyle: TextStyle(fontSize: 13, height: 18 / 13, color: t.inkFaint),
        border: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.zero,
        prefixIcon: const ExcludeSemantics(child: Icon(Icons.search, size: 19)),
        prefixIconColor: t.inkFaint,
        prefixIconConstraints: const BoxConstraints(
          minWidth: 40,
          minHeight: 40,
        ),
        suffixIcon: _hasText
            ? Semantics(
                button: true,
                label: 'Clear search',
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: IconButton(
                    onPressed: _clear,
                    tooltip: 'Clear search',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 40,
                      height: 40,
                    ),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ),
              )
            : null,
        suffixIconColor: t.inkFaint,
        suffixIconConstraints: const BoxConstraints(
          minWidth: 40,
          minHeight: 40,
        ),
      ),
    );
  }

  Widget _buildClosedPill(BuildContext context, ColorTokens t) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: _requestFocus,
      child: Row(
        children: [
          ExcludeSemantics(
            child: Icon(Icons.search, size: 19, color: t.inkFaint),
          ),
          const SizedBox(width: 8),
          Text(
            'Search chats',
            style: TextStyle(fontSize: 13, height: 18 / 13, color: t.inkFaint),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Semantics(
      textField: true,
      label: 'Search chats',
      child: SizedBox(
        width: double.infinity,
        child: AnimatedContainer(
          duration: motionOf(context, WarmPopTokens.motionFast),
          curve: WarmPopTokens.curveEnter,
          height: 44,
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: _hasFocus ? t.accent : t.line,
              width: _hasFocus ? 1.5 : 1,
            ),
          ),
          child: _hasFocus || _hasText
              ? _buildField(context, t)
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildClosedPill(context, t),
                ),
        ),
      ),
    );
  }
}
