import 'package:flutter/material.dart';

/// Right-column dynamic zone for §7.5 wizard screens.
///
/// Minimal slot that hosts the per-screen dynamic content (selection list,
/// preview, progress, logs). Intentionally thin — screens compose the
/// specific tree (Column / AnimatedSwitcher / Stack) inside the [child].
class DynamicZonePanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const DynamicZonePanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(padding: padding, child: child);
  }
}
