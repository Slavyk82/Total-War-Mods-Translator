// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'theme_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Theme notifier using AsyncNotifier to properly handle async initialization
///
/// This prevents the race condition where the UI displays with the default
/// theme before the saved theme is loaded from SharedPreferences.

@ProviderFor(ThemeNotifier)
const themeProvider = ThemeNotifierProvider._();

/// Theme notifier using AsyncNotifier to properly handle async initialization
///
/// This prevents the race condition where the UI displays with the default
/// theme before the saved theme is loaded from SharedPreferences.
final class ThemeNotifierProvider
    extends $AsyncNotifierProvider<ThemeNotifier, ThemeMode> {
  /// Theme notifier using AsyncNotifier to properly handle async initialization
  ///
  /// This prevents the race condition where the UI displays with the default
  /// theme before the saved theme is loaded from SharedPreferences.
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

String _$themeNotifierHash() => r'0d164bca5bc72977725105b4dcc3765d8d449c04';

/// Theme notifier using AsyncNotifier to properly handle async initialization
///
/// This prevents the race condition where the UI displays with the default
/// theme before the saved theme is loaded from SharedPreferences.

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
