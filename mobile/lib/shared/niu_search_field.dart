import 'package:flutter/material.dart';
import 'niu_icons.dart';

/// Filled pill search field with an inline clear action.
class NiuSearchField extends StatefulWidget {
  const NiuSearchField({
    super.key,
    this.controller,
    this.hint = '搜尋',
    this.onChanged,
  });
  final TextEditingController? controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  @override
  State<NiuSearchField> createState() => _NiuSearchFieldState();
}

class _NiuSearchFieldState extends State<NiuSearchField> {
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
            prefixIcon: const Icon(NiuIcons.search),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(999),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(999),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(999),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 1.5,
              ),
            ),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    tooltip: '清除搜尋',
                    onPressed: () {
                      controller.clear();
                      widget.onChanged?.call('');
                    },
                    icon: const Icon(NiuIcons.clear, size: 20),
                  ),
          ),
        ),
      );
}
