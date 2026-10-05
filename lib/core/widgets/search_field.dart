import 'package:flutter/material.dart';
import '../../core/theme/tokens.dart';

class SearchField extends StatelessWidget {
  const SearchField(
      {super.key, required this.onChanged, this.hint, this.controller});
  final ValueChanged<String> onChanged;
  final String? hint;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return SizedBox(
      height: 44,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(fontSize: 15, color: t.ink),
        decoration: InputDecoration(
          hintText: hint ?? 'Search',
          hintStyle: TextStyle(fontSize: 15, color: t.inkFaint),
          prefixIcon: Icon(Icons.search, color: t.inkFaint, size: 20),
          filled: true,
          fillColor: t.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide(color: t.line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide(color: t.accent, width: 1.5),
          ),
        ),
      ),
    );
  }
}
