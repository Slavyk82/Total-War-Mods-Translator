import 'package:flutter/material.dart';

/// 2-column layout for the body of a detail screen (§7.2).
///
/// Above [stackBreakpoint] the layout is a Row of `Expanded(main)` and a
/// fixed-width `rail`. Below, both widgets stack vertically in a Column.
/// Padding is 24px on all sides; gap between main and rail is [gap].
class DetailOverviewLayout extends StatelessWidget {
  final Widget main;
  final Widget rail;
  final double railWidth;
  final double gap;
  final double stackBreakpoint;
  final EdgeInsetsGeometry padding;

  const DetailOverviewLayout({
    super.key,
    required this.main,
    required this.rail,
    this.railWidth = 320,
    this.gap = 24,
    this.stackBreakpoint = 1000,
    this.padding = const EdgeInsets.all(24),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth >= stackBreakpoint) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: main),
              SizedBox(width: gap),
              SizedBox(width: railWidth, child: rail),
            ],
          );
        }
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              main,
              SizedBox(height: gap),
              rail,
            ],
          ),
        );
      }),
    );
  }
}
