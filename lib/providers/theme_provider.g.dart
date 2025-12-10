// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'theme_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Theme notifier using AsyncNotifier to properly handle async initialization
///
/// Supports three modes: system (synced with Windows), light, and dark.
/// Default is system mode to respect user's Windows preferences.

@ProviderFor(ThemeNotifier)
const themeProvider = ThemeNotifierProvider._();

/// Theme notifier using AsyncNotifier to properly handle async initialization
///
/// Supports three modes: system (synced with Windows), light, and dark.
/// Default is system mode to respect user's Windows preferences.
final class ThemeNotifierProvider
    extends $AsyncNotifierProvider<ThemeNotifier, ThemeMode> {
  /// Theme notifier using AsyncNotifier to properly handle async initialization
  ///
  /// Supports three modes: system (synced with Windows), light, and dark.
  /// Default is system mode to respect user's Windows preferences.
  const ThemeNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'themeProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$themeNotifierHash();

  @$internal
  @override
  ThemeNotifier create() => ThemeNotifier();
}

String _$themeNotifierHash() => r'41684adb029b6816bd7fa5a3ab96c15e482b1ac0';

/// Theme notifier using AsyncNotifier to properly handle async initialization
///
/// Supports three modes: system (synced with Windows), light, and dark.
/// Default is system mode to respect user's Windows preferences.

abstract class _$ThemeNotifier extends $AsyncNotifier<ThemeMode> {
  FutureOr<ThemeMode> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<AsyncValue<ThemeMode>, ThemeMode>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<ThemeMode>, ThemeMode>,
              AsyncValue<ThemeMode>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
