import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:twmt/features/settings/providers/settings_providers.dart'
    hide settingsServiceProvider;
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

/// Pedagogical onboarding card surfaced on the Steam Workshop publish screen.
///
/// The first Workshop publication has to happen through the in-game launcher
/// because only the game client is authorised to create a brand-new Workshop
/// item; subsequent updates can be automated from this screen once the user
/// pastes back the Workshop ID. This card exists to make that two-phase flow
/// discoverable without forcing a dialog.
///
/// Behaviour (workflow-improvements design · Decision 6):
///
/// - Renders every session by default.
/// - A "Don't show this again" checkbox toggles opt-in persistence: ticking
///   it AND tapping Dismiss stores
///   [SettingsKeys.workshopOnboardingCardHidden] = `true` so the card stays
///   hidden until the user explicitly resets onboarding hints in Settings.
/// - Tapping Dismiss without ticking the checkbox hides the card for the
///   current session only.
///
/// The card deliberately reads/writes the settings service directly rather
/// than introducing a dedicated provider — the state is UI-local and tiny,
/// and adding a Riverpod notifier would obscure the intent.
class WorkshopOnboardingCard extends ConsumerStatefulWidget {
  const WorkshopOnboardingCard({super.key});

  @override
  ConsumerState<WorkshopOnboardingCard> createState() =>
      _WorkshopOnboardingCardState();
}

class _WorkshopOnboardingCardState
    extends ConsumerState<WorkshopOnboardingCard> {
  /// Whether the async settings read has resolved. Before this flips true we
  /// render an empty box so the card doesn't flash visible then vanish.
  bool _loaded = false;

  /// Mirror of the persisted flag after the initial read.
  bool _persistedHidden = false;

  /// Session-only dismissal — set when Dismiss is tapped without the opt-in
  /// checkbox ticked.
  bool _hiddenForSession = false;

  /// Current state of the "Don't show this again" checkbox.
  bool _dontShowAgain = false;

  @override
  void initState() {
    super.initState();
    _loadPersistedFlag();
  }

  Future<void> _loadPersistedFlag() async {
    bool hidden = false;
    try {
      final service = ref.read(settingsServiceProvider);
      hidden = await service.getBool(
        SettingsKeys.workshopOnboardingCardHidden,
      );
    } catch (_) {
      // Settings service unavailable (e.g. in unconfigured tests) — treat as
      // not hidden so the card still renders.
      hidden = false;
    }
    if (!mounted) return;
    setState(() {
      _persistedHidden = hidden;
      _loaded = true;
    });
  }

  Future<void> _onDismiss() async {
    if (_dontShowAgain) {
      try {
        final service = ref.read(settingsServiceProvider);
        await service.setBool(
          SettingsKeys.workshopOnboardingCardHidden,
          true,
        );
      } catch (_) {
        // Persistence failures are silent — the card still hides for the
        // current session, and next launch the user will just see it again.
      }
    }
    if (!mounted) return;
    setState(() => _hiddenForSession = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _persistedHidden || _hiddenForSession) {
      return const SizedBox.shrink();
    }

    final tokens = context.tokens;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      decoration: BoxDecoration(
        color: tokens.accentBg,
        border: Border.all(color: tokens.accent.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
      ),
      // A Material ancestor is required for the Checkbox ink + focus layers.
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    FluentIcons.info_24_regular,
                    size: 18,
                    color: tokens.accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Publishing on the Steam Workshop',
                      style: tokens.fontDisplay.copyWith(
                        fontSize: 14,
                        color: tokens.text,
                        fontWeight: FontWeight.w600,
                        fontStyle: tokens.fontDisplayStyle,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'This app cannot create a brand-new Workshop entry directly. '
                'A bug in the game launcher prevents mods uploaded outside of '
                'it from appearing in subscribers\' launchers, so the very '
                'first publication of a translation mod must go through the '
                'original game launcher. Every subsequent update can then be '
                'pushed straight from this screen.',
                style: tokens.fontBody.copyWith(
                  fontSize: 12.5,
                  color: tokens.textMid,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 10),
              _OnboardingStep(
                index: 1,
                text: 'Publish the mod once through the original game '
                    'launcher.',
              ),
              const SizedBox(height: 4),
              _OnboardingStep(
                index: 2,
                text: 'Copy the Workshop ID assigned by Steam : it appears in '
                    'the mod\'s Workshop URL (e.g. "3661242610").',
              ),
              const SizedBox(height: 4),
              _OnboardingStep(
                index: 3,
                text: 'Paste that ID into the dedicated field for this mod in '
                    'the app.',
              ),
              const SizedBox(height: 4),
              _OnboardingStep(
                index: 4,
                text: 'Use the "Update" button to push every future '
                    'translation update from this screen.',
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  SizedBox(
                    height: 24,
                    width: 24,
                    child: Checkbox(
                      value: _dontShowAgain,
                      onChanged: (v) =>
                          setState(() => _dontShowAgain = v ?? false),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "Don't show this again",
                    style: tokens.fontBody.copyWith(
                      fontSize: 12.5,
                      color: tokens.textMid,
                    ),
                  ),
                  const Spacer(),
                  SmallTextButton(
                    label: 'Dismiss',
                    icon: FluentIcons.checkmark_24_regular,
                    onTap: _onDismiss,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingStep extends StatelessWidget {
  final int index;
  final String text;

  const _OnboardingStep({required this.index, required this.text});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final textStyle = tokens.fontBody.copyWith(
      fontSize: 12.5,
      color: tokens.textMid,
      height: 1.4,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 18,
          child: Text(
            '$index.',
            style: textStyle.copyWith(
              color: tokens.text,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(child: Text(text, style: textStyle)),
      ],
    );
  }
}
