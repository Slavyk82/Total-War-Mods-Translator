import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Column sizing for [ListRow] and [ListRowHeader].
/// `fixed(px)` reserves exact pixels. `flex(n)` distributes remaining space
/// proportionally. At most 2 flex columns recommended per §7.1.
sealed class ListRowColumn {
  const ListRowColumn();
  const factory ListRowColumn.fixed(double width) = _Fixed;
  const factory ListRowColumn.flex(int weight) = _Flex;
}

final class _Fixed extends ListRowColumn {
  final double width;
  const _Fixed(this.width);
}

final class _Flex extends ListRowColumn {
  final int weight;
  const _Flex(this.weight);
}

/// Grid-column row for §7.1 card lists. Fixed column widths prevent vertical
/// misalignment between rows. Border-left accent 2px when [selected].
class ListRow extends StatelessWidget {
  final List<ListRowColumn> columns;
  final List<Widget> children;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? trailingAction;
  final double height;

  const ListRow({
    super.key,
    required this.columns,
    required this.children,
    this.selected = false,
    this.onTap,
    this.trailingAction,
    this.height = 56,
  }) : assert(columns.length == children.length, 'columns.length must equal children.length');

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final bg = selected ? tokens.rowSelected : tokens.panel2;
    final content = Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          left: BorderSide(color: selected ? tokens.accent : Colors.transparent, width: 2),
          bottom: BorderSide(color: tokens.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          for (var i = 0; i < columns.length; i++) _cell(columns[i], children[i]),
          if (trailingAction != null) ...[const SizedBox(width: 8), trailingAction!],
        ],
      ),
    );
    if (onTap != null) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(onTap: onTap, child: content),
      );
    }
    return content;
  }

  Widget _cell(ListRowColumn col, Widget child) {
    return switch (col) {
      _Fixed(:final width) => SizedBox(width: width, child: child),
      _Flex(:final weight) => Expanded(flex: weight, child: child),
    };
  }
}

/// Header row mirror of [ListRow]. Labels rendered in mono 10-11px caps.
class ListRowHeader extends StatelessWidget {
  final List<ListRowColumn> columns;
  final List<String> labels;
  final double height;

  const ListRowHeader({
    super.key,
    required this.columns,
    required this.labels,
    this.height = 32,
  }) : assert(columns.length == labels.length);

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final style = tokens.fontMono.copyWith(fontSize: 11, color: tokens.textDim, letterSpacing: 0.8);
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: tokens.panel,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < columns.length; i++)
            _cell(columns[i], Text(labels[i].toUpperCase(), style: style)),
        ],
      ),
    );
  }

  Widget _cell(ListRowColumn col, Widget child) {
    return switch (col) {
      _Fixed(:final width) => SizedBox(width: width, child: child),
      _Flex(:final weight) => Expanded(flex: weight, child: child),
    };
  }
}
