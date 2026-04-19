import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/dialogs/token_dialog.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import '../../providers/data_migration_provider.dart';

/// Token-themed modal showing data-migration progress.
///
/// Non-dismissible; blocks the UI until migrations complete.
class DataMigrationDialog extends ConsumerStatefulWidget {
  const DataMigrationDialog({super.key});

  /// Show the migration dialog and wait for completion.
  static Future<void> showAndRun(BuildContext context, WidgetRef ref) async {
    final needsMigration =
        await ref.read(dataMigrationProvider.notifier).needsMigration();

    if (!needsMigration) return;
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const DataMigrationDialog(),
    );
  }

  @override
  ConsumerState<DataMigrationDialog> createState() =>
      _DataMigrationDialogState();
}

class _DataMigrationDialogState extends ConsumerState<DataMigrationDialog> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(dataMigrationProvider.notifier).runMigrations();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final state = ref.watch(dataMigrationProvider);

    if (state.isComplete) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pop();
        }
      });
    }

    return PopScope(
      canPop: false,
      child: TokenDialog(
        icon: FluentIcons.database_arrow_right_24_regular,
        title: 'Database Update',
        subtitle: 'One-time migration required',
        width: 500,
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.error != null) ...[
              _buildErrorBanner(tokens, state.error!),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: SmallTextButton(
                  label: 'Retry',
                  icon: FluentIcons.arrow_clockwise_24_regular,
                  filled: true,
                  onTap: () => ref
                      .read(dataMigrationProvider.notifier)
                      .runMigrations(),
                ),
              ),
            ] else ...[
              Text(
                state.currentStep.isEmpty
                    ? 'Preparing...'
                    : state.currentStep,
                style: tokens.fontBody.copyWith(
                  fontSize: 14,
                  color: tokens.text,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                state.progressMessage,
                style: tokens.fontBody.copyWith(
                  fontSize: 12.5,
                  color: tokens.textDim,
                ),
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(tokens.radiusSm),
                child: LinearProgressIndicator(
                  value: state.totalProgress > 0
                      ? state.progressPercent
                      : null,
                  minHeight: 8,
                  backgroundColor: tokens.panel2,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(tokens.accent),
                ),
              ),
              if (state.totalProgress > 0) ...[
                const SizedBox(height: 6),
                Text(
                  '${(state.progressPercent * 100).toInt()}%',
                  style: tokens.fontBody.copyWith(
                    fontSize: 11.5,
                    color: tokens.textDim,
                  ),
                ),
              ],
            ],
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: tokens.infoBg,
                borderRadius: BorderRadius.circular(tokens.radiusSm),
                border: Border.all(
                  color: tokens.info.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    FluentIcons.info_24_regular,
                    size: 18,
                    color: tokens.info,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'This process ensures Translation Memory works '
                      'correctly. Please do not close the application.',
                      style: tokens.fontBody.copyWith(
                        fontSize: 12,
                        color: tokens.textDim,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner(TwmtThemeTokens tokens, String error) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.errBg,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.err.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            FluentIcons.error_circle_24_regular,
            color: tokens.err,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              error,
              style: tokens.fontBody.copyWith(
                fontSize: 12.5,
                color: tokens.err,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
