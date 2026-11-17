import 'package:flutter/material.dart';

import '../theme.dart';

/// Compact search bar shared by the deadlines and notes tabs. The owning page
/// closes it from the header, so this only offers a clear button while text is
/// present.
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          return TextField(
            controller: controller,
            focusNode: focusNode,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            style: TextStyle(color: Ink0.text, fontSize: 14.5),
            cursorColor: Ink0.text,
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TextStyle(color: Ink0.muted, fontSize: 13.5),
              prefixIcon: Icon(Icons.search, size: 20, color: Ink0.muted),
              suffixIcon: value.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        controller.clear();
                        onChanged('');
                      },
                      icon: Icon(Icons.close, size: 18, color: Ink0.muted),
                    ),
              isDense: true,
              filled: true,
              fillColor: Ink0.surface,
              contentPadding: const EdgeInsets.symmetric(vertical: 11),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Ink0.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Ink0.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Ink0.muted),
              ),
            ),
          );
        },
      ),
    );
  }
}
