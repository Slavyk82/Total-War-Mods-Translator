import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/settings/settings_tab_bar.dart';
import '../widgets/general_settings_tab.dart';
import '../widgets/folders_settings_tab.dart';
import '../widgets/llm_providers_tab.dart';

/// Settings screen with a tabbed interface for General / Folders / LLM Providers.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Scaffold(
      backgroundColor: tokens.bg,
      body: DefaultTabController(
        length: 3,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                children: [
                  Icon(
                    FluentIcons.settings_24_regular,
                    size: 32,
                    color: tokens.accent,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Settings',
                    style: tokens.fontDisplay.copyWith(
                      fontSize: 24,
                      color: tokens.text,
                      fontStyle: tokens.fontDisplayStyle,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: tokens.border, width: 1),
                ),
              ),
              child: const SettingsTabBar(tabs: [
                SettingsTabItem(
                  icon: FluentIcons.settings_24_regular,
                  label: 'General',
                ),
                SettingsTabItem(
                  icon: FluentIcons.folder_24_regular,
                  label: 'Folders',
                ),
                SettingsTabItem(
                  icon: FluentIcons.brain_circuit_24_regular,
                  label: 'LLM Providers',
                ),
              ]),
            ),
            const Expanded(
              child: TabBarView(
                children: [
                  GeneralSettingsTab(),
                  FoldersSettingsTab(),
                  LlmProvidersTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
