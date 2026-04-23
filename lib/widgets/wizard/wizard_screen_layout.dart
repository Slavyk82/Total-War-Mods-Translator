import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/wizard/dynamic_zone_panel.dart';
import 'package:twmt/widgets/wizard/sticky_form_panel.dart';

/// Composition §7.5 wizard screen chrome: toolbar + sticky form + dynamic
/// zone, with an optional right-side advisory panel.
class WizardScreenLayout extends StatelessWidget {
  final Widget toolbar;
  final StickyFormPanel formPanel;
  final DynamicZonePanel dynamicZone;
  final Widget? rightPanel;

  const WizardScreenLayout({
    super.key,
    required this.toolbar,
    required this.formPanel,
    required this.dynamicZone,
    this.rightPanel,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Material(
      color: tokens.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          toolbar,
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                formPanel,
                Expanded(child: dynamicZone),
                if (rightPanel != null) rightPanel!,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
