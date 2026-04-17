import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'settings_section_header.dart';
import '../../providers/maintenance_providers.dart';

/// Database maintenance section for settings.
///
/// Provides actions to maintain and fix database statistics,
/// such as reanalyzing all translations to detect untranslated units.
class MaintenanceSection extends ConsumerWidget {
  const MaintenanceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final maintenanceState = ref.watch(maintenanceStateProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader(
          title: 'Database Maintenance',
          subtitle:
              'Tools to maintain and fix database statistics and translation states.',
        ),
        const SizedBox(height: 16),
        _buildMaintenanceCard(context, ref, maintenanceState),
      ],
    );
  }

  Widget _buildMaintenanceCard(
    BuildContext context,
    WidgetRef ref,
    MaintenanceState state,
  ) {
    final tokens = context.tokens;
    final isRunning = state.isReanalyzing;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.panel,
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                FluentIcons.wrench_24_regular,
                size: 24,
                color: tokens.accent,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Maintenance Actions',
                  style: tokens.fontBody.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: tokens.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (state.lastResult != null) ...[
            _buildResultMessage(context, state.lastResult!),
            const SizedBox(height: 16),
          ],
          if (isRunning) ...[
            Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: tokens.accent,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  state.progressMessage ?? 'Processing...',
                  style: tokens.fontBody.copyWith(
                    fontSize: 13,
                    color: tokens.text,
                  ),
                ),
              ],
            ),
          ] else ...[
            _buildActionRow(
              context,
              ref,
              icon: FluentIcons.arrow_sync_24_regular,
              title: 'Reanalyze Translations',
              description: 'Fix status inconsistencies and detect untranslated units',
              onTap: () => _runReanalysis(ref),
              isPrimary: true,
            ),
            const SizedBox(height: 12),
            _buildActionRow(
              context,
              ref,
              icon: FluentIcons.delete_24_regular,
              title: 'Clear Mod Update Cache',
              description: 'Remove stale "pending changes" badges',
              onTap: () => _clearCache(ref),
              isPrimary: false,
            ),
            const SizedBox(height: 12),
            _buildActionRow(
              context,
              ref,
              icon: FluentIcons.database_24_regular,
              title: 'Rebuild Translation Memory',
              description: 'Recover missing TM entries from existing translations',
              onTap: () => _rebuildTranslationMemory(ref),
              isPrimary: false,
            ),
            const SizedBox(height: 12),
            _buildActionRow(
              context,
              ref,
              icon: FluentIcons.arrow_sync_24_regular,
              title: 'Migrate Legacy TM Hashes',
              description: 'Convert old integer hashes to SHA256 for TM lookup',
              onTap: () => _migrateLegacyHashes(ref),
              isPrimary: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionRow(
    BuildContext context,
    WidgetRef ref, {
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
    required bool isPrimary,
  }) {
    final tokens = context.tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isPrimary ? tokens.accentBg : tokens.panel2,
            borderRadius: BorderRadius.circular(tokens.radiusMd),
            border: Border.all(color: tokens.border),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: isPrimary ? tokens.accent : tokens.textDim,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: tokens.fontBody.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: tokens.text,
                      ),
                    ),
                    Text(
                      description,
                      style: tokens.fontBody.copyWith(
                        fontSize: 12,
                        color: tokens.textDim,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                FluentIcons.chevron_right_24_regular,
                size: 16,
                color: tokens.textDim,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultMessage(
    BuildContext context,
    MaintenanceResult result,
  ) {
    final tokens = context.tokens;
    final isSuccess = result.success;
    final color = isSuccess ? tokens.ok : tokens.err;
    final bgColor = isSuccess ? tokens.okBg : tokens.errBg;
    final icon = isSuccess
        ? FluentIcons.checkmark_circle_24_regular
        : FluentIcons.error_circle_24_regular;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              result.message,
              style: tokens.fontBody.copyWith(fontSize: 12, color: color),
            ),
          ),
        ],
      ),
    );
  }

  void _runReanalysis(WidgetRef ref) {
    ref.read(maintenanceStateProvider.notifier).reanalyzeAllTranslations();
  }

  void _clearCache(WidgetRef ref) {
    ref.read(maintenanceStateProvider.notifier).clearStaleAnalysisCache();
  }

  void _rebuildTranslationMemory(WidgetRef ref) {
    ref.read(maintenanceStateProvider.notifier).rebuildTranslationMemory();
  }

  void _migrateLegacyHashes(WidgetRef ref) {
    ref.read(maintenanceStateProvider.notifier).migrateLegacyHashes();
  }
}
