import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import '../providers/translation_settings_provider.dart';

/// Inline batch-settings panel rendered in the editor sidebar §Context group.
///
/// Exposes three controls previously hidden behind the `TranslationSettings`
/// dialog:
/// - Auto toggle (`unitsPerBatch == 0` means auto)
/// - Units per batch (1–1000, disabled while Auto is on)
/// - Parallel batches (1–20)
///
/// Writes are committed on focus loss, submit (Enter) and switch toggle via
/// `translationSettingsProvider.updateSettings`, which persists to
/// SharedPreferences.
class EditorToolbarBatchSettings extends ConsumerStatefulWidget {
  const EditorToolbarBatchSettings({super.key});

  @override
  ConsumerState<EditorToolbarBatchSettings> createState() =>
      _EditorToolbarBatchSettingsState();
}

class _EditorToolbarBatchSettingsState
    extends ConsumerState<EditorToolbarBatchSettings> {
  late final TextEditingController _unitsController;
  late final TextEditingController _parallelController;
  late final FocusNode _unitsFocus;
  late final FocusNode _parallelFocus;

  @override
  void initState() {
    super.initState();
    _unitsController = TextEditingController();
    _parallelController = TextEditingController();
    _unitsFocus = FocusNode(debugLabel: 'editor-units-per-batch')
      ..addListener(_onUnitsFocusChange);
    _parallelFocus = FocusNode(debugLabel: 'editor-parallel-batches')
      ..addListener(_onParallelFocusChange);
    // Kick off the async prefs load so persisted values land before the user
    // has a chance to tweak anything.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(translationSettingsProvider.notifier).ensureLoaded();
    });
  }

  @override
  void dispose() {
    _unitsFocus.removeListener(_onUnitsFocusChange);
    _parallelFocus.removeListener(_onParallelFocusChange);
    _unitsController.dispose();
    _parallelController.dispose();
    _unitsFocus.dispose();
    _parallelFocus.dispose();
    super.dispose();
  }

  void _onUnitsFocusChange() {
    if (!_unitsFocus.hasFocus) _commitUnits();
  }

  void _onParallelFocusChange() {
    if (!_parallelFocus.hasFocus) _commitParallel();
  }

  void _commitUnits() {
    final current = ref.read(translationSettingsProvider);
    if (current.isAutoMode) return;
    final parsed = int.tryParse(_unitsController.text);
    final clamped = (parsed ?? current.unitsPerBatch).clamp(1, 1000);
    if (_unitsController.text != clamped.toString()) {
      _unitsController.text = clamped.toString();
    }
    if (clamped != current.unitsPerBatch) {
      ref.read(translationSettingsProvider.notifier).updateSettings(
            unitsPerBatch: clamped,
            parallelBatches: current.parallelBatches,
          );
    }
  }

  void _commitParallel() {
    final current = ref.read(translationSettingsProvider);
    final parsed = int.tryParse(_parallelController.text);
    final clamped = (parsed ?? current.parallelBatches).clamp(1, 20);
    if (_parallelController.text != clamped.toString()) {
      _parallelController.text = clamped.toString();
    }
    if (clamped != current.parallelBatches) {
      ref.read(translationSettingsProvider.notifier).updateSettings(
            unitsPerBatch: current.unitsPerBatch,
            parallelBatches: clamped,
          );
    }
  }

  void _toggleAuto(bool isAuto) {
    final current = ref.read(translationSettingsProvider);
    final nextUnits = isAuto
        ? 0
        : (int.tryParse(_unitsController.text) ?? 100).clamp(1, 1000);
    ref.read(translationSettingsProvider.notifier).updateSettings(
          unitsPerBatch: nextUnits,
          parallelBatches: current.parallelBatches,
        );
  }

  // Keep controllers synchronised with persisted state when the field is
  // unfocused (e.g. after the async load resolves). Avoids clobbering a
  // user's in-flight edit.
  void _syncControllers(TranslationSettings settings) {
    if (!_unitsFocus.hasFocus) {
      final expected =
          settings.isAutoMode ? '' : settings.unitsPerBatch.toString();
      if (_unitsController.text != expected) {
        _unitsController.text = expected;
      }
    }
    if (!_parallelFocus.hasFocus) {
      final expected = settings.parallelBatches.toString();
      if (_parallelController.text != expected) {
        _parallelController.text = expected;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final settings = ref.watch(translationSettingsProvider);
    _syncControllers(settings);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: tokens.panel2,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildAutoRow(tokens, settings),
          const SizedBox(height: 6),
          _buildUnitsRow(tokens, settings),
          const SizedBox(height: 6),
          _buildParallelRow(tokens, settings),
        ],
      ),
    );
  }

  Widget _buildAutoRow(TwmtThemeTokens tokens, TranslationSettings settings) {
    return Tooltip(
      message: t.tooltips.editor.batchAuto,
      waitDuration: const Duration(milliseconds: 500),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Auto batch size',
              overflow: TextOverflow.ellipsis,
              style: tokens.fontBody.copyWith(
                fontSize: 12,
                color: tokens.text,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SizedBox(
            height: 24,
            child: Switch(
              value: settings.isAutoMode,
              onChanged: _toggleAuto,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnitsRow(TwmtThemeTokens tokens, TranslationSettings settings) {
    final enabled = !settings.isAutoMode;
    return Tooltip(
      message: t.tooltips.editor.batchUnits,
      waitDuration: const Duration(milliseconds: 500),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Units / batch',
              overflow: TextOverflow.ellipsis,
              style: tokens.fontBody.copyWith(
                fontSize: 12,
                color: enabled ? tokens.text : tokens.textFaint,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SizedBox(
            width: 56,
            child: _numberField(
              tokens: tokens,
              controller: _unitsController,
              focusNode: _unitsFocus,
              enabled: enabled,
              onSubmitted: (_) => _commitUnits(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParallelRow(
    TwmtThemeTokens tokens,
    TranslationSettings settings,
  ) {
    return Tooltip(
      message: t.tooltips.editor.batchParallel,
      waitDuration: const Duration(milliseconds: 500),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Parallel batches',
              overflow: TextOverflow.ellipsis,
              style: tokens.fontBody.copyWith(
                fontSize: 12,
                color: tokens.text,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SizedBox(
            width: 56,
            child: _numberField(
              tokens: tokens,
              controller: _parallelController,
              focusNode: _parallelFocus,
              enabled: true,
              onSubmitted: (_) => _commitParallel(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _numberField({
    required TwmtThemeTokens tokens,
    required TextEditingController controller,
    required FocusNode focusNode,
    required bool enabled,
    required ValueChanged<String> onSubmitted,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      textAlign: TextAlign.center,
      textInputAction: TextInputAction.done,
      onSubmitted: onSubmitted,
      style: tokens.fontBody.copyWith(
        fontSize: 12,
        color: enabled ? tokens.text : tokens.textFaint,
      ),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: enabled ? tokens.panel : tokens.panel2,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 6,
          vertical: 6,
        ),
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
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          borderSide:
              BorderSide(color: tokens.border.withValues(alpha: 0.4)),
        ),
      ),
    );
  }
}
