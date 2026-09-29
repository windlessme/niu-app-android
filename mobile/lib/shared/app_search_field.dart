import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class AppSearchField extends StatefulWidget {
  const AppSearchField({
    super.key,
    this.controller,
    this.hint = '搜尋',
    this.onChanged,
  });
  final TextEditingController? controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  late final local = TextEditingController();
  TextEditingController get controller => widget.controller ?? local;
  @override
  void dispose() {
    local.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => TextField(
          controller: controller,
          onChanged: widget.onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: widget.hint,
            prefixIcon: const Icon(CupertinoIcons.search),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    tooltip: '清除搜尋',
                    onPressed: () {
                      controller.clear();
                      widget.onChanged?.call('');
                    },
                    icon: const Icon(CupertinoIcons.clear_circled_solid),
                  ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 1,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
        ),
      );
}
