import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Compact token-themed search field used in the toolbar row of §7.1
/// filterable list archetypes.
///
/// Height 32, panel2 background, radiusSm border, prefix search icon,
/// suffix clear icon rendered when [value] is non-empty (and [onClear] is set).
/// Synchronises with an external [value] so callers driving state from a
/// Riverpod notifier can reset the field (e.g. on filter reset).
class ListSearchField extends StatefulWidget {
  /// Current search text, typically read from a filter provider.
  final String value;

  /// Placeholder text shown when empty.
  final String hintText;

  /// Fired on every keystroke.
  final ValueChanged<String> onChanged;

  /// Fired when the clear icon is tapped. When null, the clear icon is hidden.
  final VoidCallback? onClear;

  /// Overall field width. When null, the field expands to fill the width
  /// provided by its parent (e.g. inside an [Expanded] or [Flexible]).
  final double? width;

  /// Optional external focus node. When provided, external controllers (e.g.
  /// keyboard shortcuts) can request focus on the field.
  final FocusNode? focusNode;

  const ListSearchField({
    super.key,
    required this.value,
    required this.onChanged,
    this.hintText = 'Search...',
    this.onClear,
    this.width = 260,
    this.focusNode,
  });

  @override
  State<ListSearchField> createState() => _ListSearchFieldState();
}

class _ListSearchFieldState extends State<ListSearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant ListSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.value = _controller.value.copyWith(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SizedBox(
      width: widget.width,
      height: 32,
      child: TextField(
        controller: _controller,
        focusNode: widget.focusNode,
        style: tokens.fontBody.copyWith(fontSize: 13, color: tokens.text),
        onChanged: widget.onChanged,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: tokens.panel2,
          hintText: widget.hintText,
          hintStyle: tokens.fontBody.copyWith(
            fontSize: 13,
            color: tokens.textFaint,
          ),
          prefixIcon: Icon(
            FluentIcons.search_24_regular,
            size: 16,
            color: tokens.textDim,
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 32, minHeight: 32),
          suffixIcon: (widget.onClear != null && _controller.text.isNotEmpty)
              ? MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      _controller.clear();
                      widget.onClear!();
                    },
                    child: Icon(
                      FluentIcons.dismiss_circle_24_regular,
                      size: 16,
                      color: tokens.textDim,
                    ),
                  ),
                )
              : null,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            borderSide: BorderSide(color: tokens.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            borderSide: BorderSide(color: tokens.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            borderSide: BorderSide(color: tokens.accent),
          ),
        ),
      ),
    );
  }
}
