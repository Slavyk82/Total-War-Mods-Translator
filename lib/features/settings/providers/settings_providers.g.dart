// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider for settings service

@ProviderFor(settingsService)
const settingsServiceProvider = SettingsServiceProvider._();

/// Provider for settings service

final class SettingsServiceProvider
    extends
        $FunctionalProvider<SettingsService, SettingsService, SettingsService>
    with $Provider<SettingsService> {
  /// Provider for settings service
  const SettingsServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'settingsServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$settingsServiceHash();

  @$internal
  @override
  $ProviderElement<SettingsService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SettingsService create(Ref ref) {
    return settingsService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SettingsService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SettingsService>(value),
    );
  }
}

String _$settingsServiceHash() => r'f5cba4a57a672bddc8dcd8d205f19cbaa744d216';

/// Provider for LLM model management service

@ProviderFor(llmModelManagementService)
const llmModelManagementServiceProvider = LlmModelManagementServiceProvider._();

/// Provider for LLM model management service

final class LlmModelManagementServiceProvider
    extends
        $FunctionalProvider<
          LlmModelManagementService,
          LlmModelManagementService,
          LlmModelManagementService
        >
    with $Provider<LlmModelManagementService> {
  /// Provider for LLM model management service
  const LlmModelManagementServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'llmModelManagementServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$llmModelManagementServiceHash();

  @$internal
  @override
  $ProviderElement<LlmModelManagementService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  LlmModelManagementService create(Ref ref) {
    return llmModelManagementService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LlmModelManagementService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LlmModelManagementService>(value),
    );
  }
}

String _$llmModelManagementServiceHash() =>
    r'36ad31f96954b07411e3c8593bb2b1da7158de53';

/// General settings notifier

@ProviderFor(GeneralSettings)
const generalSettingsProvider = GeneralSettingsProvider._();

/// General settings notifier
final class GeneralSettingsProvider
    extends $AsyncNotifierProvider<GeneralSettings, Map<String, String>> {
  /// General settings notifier
  const GeneralSettingsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'generalSettingsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$generalSettingsHash();

  @$internal
  @override
  GeneralSettings create() => GeneralSettings();
}

String _$generalSettingsHash() => r'f030e1d95f3b3134479225ccdaf235b5375521e4';

/// General settings notifier

abstract class _$GeneralSettings extends $AsyncNotifier<Map<String, String>> {
  FutureOr<Map<String, String>> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref =
        this.ref as $Ref<AsyncValue<Map<String, String>>, Map<String, String>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<Map<String, String>>, Map<String, String>>,
              AsyncValue<Map<String, String>>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// LLM provider settings notifier

@ProviderFor(LlmProviderSettings)
const llmProviderSettingsProvider = LlmProviderSettingsProvider._();

/// LLM provider settings notifier
final class LlmProviderSettingsProvider
    extends $AsyncNotifierProvider<LlmProviderSettings, Map<String, String>> {
  /// LLM provider settings notifier
  const LlmProviderSettingsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'llmProviderSettingsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$llmProviderSettingsHash();

  @$internal
  @override
  LlmProviderSettings create() => LlmProviderSettings();
}

String _$llmProviderSettingsHash() =>
    r'b9711ebc9163d2e4e34c855a346a38f26ec23881';

/// LLM provider settings notifier

abstract class _$LlmProviderSettings
    extends $AsyncNotifier<Map<String, String>> {
  FutureOr<Map<String, String>> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref =
        this.ref as $Ref<AsyncValue<Map<String, String>>, Map<String, String>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<Map<String, String>>, Map<String, String>>,
              AsyncValue<Map<String, String>>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Provider for available LLM models for a specific provider

@ProviderFor(LlmModels)
const llmModelsProvider = LlmModelsFamily._();

/// Provider for available LLM models for a specific provider
final class LlmModelsProvider
    extends $AsyncNotifierProvider<LlmModels, List<LlmProviderModel>> {
  /// Provider for available LLM models for a specific provider
  const LlmModelsProvider._({
    required LlmModelsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'llmModelsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$llmModelsHash();

  @override
  String toString() {
    return r'llmModelsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  LlmModels create() => LlmModels();

  @override
  bool operator ==(Object other) {
    return other is LlmModelsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$llmModelsHash() => r'4065f2b4c3a0b88f1d7fd3b05a2e135ab25ff6f9';

/// Provider for available LLM models for a specific provider

final class LlmModelsFamily extends $Family
    with
        $ClassFamilyOverride<
          LlmModels,
          AsyncValue<List<LlmProviderModel>>,
          List<LlmProviderModel>,
          FutureOr<List<LlmProviderModel>>,
          String
        > {
  const LlmModelsFamily._()
    : super(
        retry: null,
        name: r'llmModelsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Provider for available LLM models for a specific provider

  LlmModelsProvider call(String providerCode) =>
      LlmModelsProvider._(argument: providerCode, from: this);

  @override
  String toString() => r'llmModelsProvider';
}

/// Provider for available LLM models for a specific provider

abstract class _$LlmModels extends $AsyncNotifier<List<LlmProviderModel>> {
  late final _$args = ref.$arg as String;
  String get providerCode => _$args;

  FutureOr<List<LlmProviderModel>> build(String providerCode);
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build(_$args);
    final ref =
        this.ref
            as $Ref<AsyncValue<List<LlmProviderModel>>, List<LlmProviderModel>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<List<LlmProviderModel>>,
                List<LlmProviderModel>
              >,
              AsyncValue<List<LlmProviderModel>>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// Provider for enabled LLM models for a specific provider

@ProviderFor(enabledLlmModels)
const enabledLlmModelsProvider = EnabledLlmModelsFamily._();

/// Provider for enabled LLM models for a specific provider

final class EnabledLlmModelsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<LlmProviderModel>>,
          List<LlmProviderModel>,
          FutureOr<List<LlmProviderModel>>
        >
    with
        $FutureModifier<List<LlmProviderModel>>,
        $FutureProvider<List<LlmProviderModel>> {
  /// Provider for enabled LLM models for a specific provider
  const EnabledLlmModelsProvider._({
    required EnabledLlmModelsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'enabledLlmModelsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$enabledLlmModelsHash();

  @override
  String toString() {
    return r'enabledLlmModelsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<LlmProviderModel>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<LlmProviderModel>> create(Ref ref) {
    final argument = this.argument as String;
    return enabledLlmModels(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is EnabledLlmModelsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$enabledLlmModelsHash() => r'ce6f81648c8a165364220da6bff75bc0ddb3a796';

/// Provider for enabled LLM models for a specific provider

final class EnabledLlmModelsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<LlmProviderModel>>, String> {
  const EnabledLlmModelsFamily._()
    : super(
        retry: null,
        name: r'enabledLlmModelsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Provider for enabled LLM models for a specific provider

  EnabledLlmModelsProvider call(String providerCode) =>
      EnabledLlmModelsProvider._(argument: providerCode, from: this);

  @override
  String toString() => r'enabledLlmModelsProvider';
}

/// Provider for the default LLM model for a specific provider

@ProviderFor(defaultLlmModel)
const defaultLlmModelProvider = DefaultLlmModelFamily._();

/// Provider for the default LLM model for a specific provider

final class DefaultLlmModelProvider
    extends
        $FunctionalProvider<
          AsyncValue<LlmProviderModel?>,
          LlmProviderModel?,
          FutureOr<LlmProviderModel?>
        >
    with
        $FutureModifier<LlmProviderModel?>,
        $FutureProvider<LlmProviderModel?> {
  /// Provider for the default LLM model for a specific provider
  const DefaultLlmModelProvider._({
    required DefaultLlmModelFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'defaultLlmModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$defaultLlmModelHash();

  @override
  String toString() {
    return r'defaultLlmModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<LlmProviderModel?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<LlmProviderModel?> create(Ref ref) {
    final argument = this.argument as String;
    return defaultLlmModel(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is DefaultLlmModelProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$defaultLlmModelHash() => r'a8ddd78236fa8da846490b2c3cd75545b4b69972';

/// Provider for the default LLM model for a specific provider

final class DefaultLlmModelFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<LlmProviderModel?>, String> {
  const DefaultLlmModelFamily._()
    : super(
        retry: null,
        name: r'defaultLlmModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Provider for the default LLM model for a specific provider

  DefaultLlmModelProvider call(String providerCode) =>
      DefaultLlmModelProvider._(argument: providerCode, from: this);

  @override
  String toString() => r'defaultLlmModelProvider';
}
