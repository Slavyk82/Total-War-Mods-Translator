// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'event_stream_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Event stream providers expose typed event streams from EventBus
///
/// These providers are lightweight adapters that don't hold state.
/// They enable selective subscription to specific event types.
// ========== Batch Event Streams ==========

@ProviderFor(batchStartedEvents)
const batchStartedEventsProvider = BatchStartedEventsProvider._();

/// Event stream providers expose typed event streams from EventBus
///
/// These providers are lightweight adapters that don't hold state.
/// They enable selective subscription to specific event types.
// ========== Batch Event Streams ==========

final class BatchStartedEventsProvider
    extends
        $FunctionalProvider<
          AsyncValue<BatchStartedEvent>,
          BatchStartedEvent,
          Stream<BatchStartedEvent>
        >
    with
        $FutureModifier<BatchStartedEvent>,
        $StreamProvider<BatchStartedEvent> {
  /// Event stream providers expose typed event streams from EventBus
  ///
  /// These providers are lightweight adapters that don't hold state.
  /// They enable selective subscription to specific event types.
  // ========== Batch Event Streams ==========
  const BatchStartedEventsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'batchStartedEventsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$batchStartedEventsHash();

  @$internal
  @override
  $StreamProviderElement<BatchStartedEvent> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<BatchStartedEvent> create(Ref ref) {
    return batchStartedEvents(ref);
  }
}

String _$batchStartedEventsHash() =>
    r'a256e56ec88d0fb4a819174c6e303cc9c648b70d';

@ProviderFor(batchProgressEvents)
const batchProgressEventsProvider = BatchProgressEventsProvider._();

final class BatchProgressEventsProvider
    extends
        $FunctionalProvider<
          AsyncValue<BatchProgressEvent>,
          BatchProgressEvent,
          Stream<BatchProgressEvent>
        >
    with
        $FutureModifier<BatchProgressEvent>,
        $StreamProvider<BatchProgressEvent> {
  const BatchProgressEventsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'batchProgressEventsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$batchProgressEventsHash();

  @$internal
  @override
  $StreamProviderElement<BatchProgressEvent> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<BatchProgressEvent> create(Ref ref) {
    return batchProgressEvents(ref);
  }
}

String _$batchProgressEventsHash() =>
    r'e2e59d05810bb30fd7bb5ebffb5d05d7761e03ec';

@ProviderFor(batchCompletedEvents)
const batchCompletedEventsProvider = BatchCompletedEventsProvider._();

final class BatchCompletedEventsProvider
    extends
        $FunctionalProvider<
          AsyncValue<BatchCompletedEvent>,
          BatchCompletedEvent,
          Stream<BatchCompletedEvent>
        >
    with
        $FutureModifier<BatchCompletedEvent>,
        $StreamProvider<BatchCompletedEvent> {
  const BatchCompletedEventsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'batchCompletedEventsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$batchCompletedEventsHash();

  @$internal
  @override
  $StreamProviderElement<BatchCompletedEvent> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<BatchCompletedEvent> create(Ref ref) {
    return batchCompletedEvents(ref);
  }
}

String _$batchCompletedEventsHash() =>
    r'bfcd84167a60a5c380144b347042221b5f39df70';

@ProviderFor(batchFailedEvents)
const batchFailedEventsProvider = BatchFailedEventsProvider._();

final class BatchFailedEventsProvider
    extends
        $FunctionalProvider<
          AsyncValue<BatchFailedEvent>,
          BatchFailedEvent,
          Stream<BatchFailedEvent>
        >
    with $FutureModifier<BatchFailedEvent>, $StreamProvider<BatchFailedEvent> {
  const BatchFailedEventsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'batchFailedEventsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$batchFailedEventsHash();

  @$internal
  @override
  $StreamProviderElement<BatchFailedEvent> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<BatchFailedEvent> create(Ref ref) {
    return batchFailedEvents(ref);
  }
}

String _$batchFailedEventsHash() => r'fd23558bb0960935eef5614d5e52452fdfbbed14';

@ProviderFor(batchPausedEvents)
const batchPausedEventsProvider = BatchPausedEventsProvider._();

final class BatchPausedEventsProvider
    extends
        $FunctionalProvider<
          AsyncValue<BatchPausedEvent>,
          BatchPausedEvent,
          Stream<BatchPausedEvent>
        >
    with $FutureModifier<BatchPausedEvent>, $StreamProvider<BatchPausedEvent> {
  const BatchPausedEventsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'batchPausedEventsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$batchPausedEventsHash();

  @$internal
  @override
  $StreamProviderElement<BatchPausedEvent> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<BatchPausedEvent> create(Ref ref) {
    return batchPausedEvents(ref);
  }
}

String _$batchPausedEventsHash() => r'1a55275172e914cd65800b07af7ec965113bc9f0';

@ProviderFor(batchResumedEvents)
const batchResumedEventsProvider = BatchResumedEventsProvider._();

final class BatchResumedEventsProvider
    extends
        $FunctionalProvider<
          AsyncValue<BatchResumedEvent>,
          BatchResumedEvent,
          Stream<BatchResumedEvent>
        >
    with
        $FutureModifier<BatchResumedEvent>,
        $StreamProvider<BatchResumedEvent> {
  const BatchResumedEventsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'batchResumedEventsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$batchResumedEventsHash();

  @$internal
  @override
  $StreamProviderElement<BatchResumedEvent> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<BatchResumedEvent> create(Ref ref) {
    return batchResumedEvents(ref);
  }
}

String _$batchResumedEventsHash() =>
    r'f8ed2f9a651675eeaadf8d19508065172569aa4d';

@ProviderFor(batchCancelledEvents)
const batchCancelledEventsProvider = BatchCancelledEventsProvider._();

final class BatchCancelledEventsProvider
    extends
        $FunctionalProvider<
          AsyncValue<BatchCancelledEvent>,
          BatchCancelledEvent,
          Stream<BatchCancelledEvent>
        >
    with
        $FutureModifier<BatchCancelledEvent>,
        $StreamProvider<BatchCancelledEvent> {
  const BatchCancelledEventsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'batchCancelledEventsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$batchCancelledEventsHash();

  @$internal
  @override
  $StreamProviderElement<BatchCancelledEvent> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<BatchCancelledEvent> create(Ref ref) {
    return batchCancelledEvents(ref);
  }
}

String _$batchCancelledEventsHash() =>
    r'852175ae9f1e28a43cb9f253b2a479748c2f38ab';

@ProviderFor(translationAddedEvents)
const translationAddedEventsProvider = TranslationAddedEventsProvider._();

final class TranslationAddedEventsProvider
    extends
        $FunctionalProvider<
          AsyncValue<TranslationAddedEvent>,
          TranslationAddedEvent,
          Stream<TranslationAddedEvent>
        >
    with
        $FutureModifier<TranslationAddedEvent>,
        $StreamProvider<TranslationAddedEvent> {
  const TranslationAddedEventsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'translationAddedEventsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$translationAddedEventsHash();

  @$internal
  @override
  $StreamProviderElement<TranslationAddedEvent> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<TranslationAddedEvent> create(Ref ref) {
    return translationAddedEvents(ref);
  }
}

String _$translationAddedEventsHash() =>
    r'72ab96d284d254830aa19b1102fe0bc2ba8aa4bf';

@ProviderFor(translationEditedEvents)
const translationEditedEventsProvider = TranslationEditedEventsProvider._();

final class TranslationEditedEventsProvider
    extends
        $FunctionalProvider<
          AsyncValue<TranslationEditedEvent>,
          TranslationEditedEvent,
          Stream<TranslationEditedEvent>
        >
    with
        $FutureModifier<TranslationEditedEvent>,
        $StreamProvider<TranslationEditedEvent> {
  const TranslationEditedEventsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'translationEditedEventsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$translationEditedEventsHash();

  @$internal
  @override
  $StreamProviderElement<TranslationEditedEvent> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<TranslationEditedEvent> create(Ref ref) {
    return translationEditedEvents(ref);
  }
}

String _$translationEditedEventsHash() =>
    r'42f99ef78614334738192a87b269ed0d114cea0a';

@ProviderFor(translationValidatedEvents)
const translationValidatedEventsProvider =
    TranslationValidatedEventsProvider._();

final class TranslationValidatedEventsProvider
    extends
        $FunctionalProvider<
          AsyncValue<TranslationValidatedEvent>,
          TranslationValidatedEvent,
          Stream<TranslationValidatedEvent>
        >
    with
        $FutureModifier<TranslationValidatedEvent>,
        $StreamProvider<TranslationValidatedEvent> {
  const TranslationValidatedEventsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'translationValidatedEventsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$translationValidatedEventsHash();

  @$internal
  @override
  $StreamProviderElement<TranslationValidatedEvent> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<TranslationValidatedEvent> create(Ref ref) {
    return translationValidatedEvents(ref);
  }
}

String _$translationValidatedEventsHash() =>
    r'7f080744cb36d365601ae01474e9553f7907c53c';

@ProviderFor(translationDeletedEvents)
const translationDeletedEventsProvider = TranslationDeletedEventsProvider._();

final class TranslationDeletedEventsProvider
    extends
        $FunctionalProvider<
          AsyncValue<TranslationDeletedEvent>,
          TranslationDeletedEvent,
          Stream<TranslationDeletedEvent>
        >
    with
        $FutureModifier<TranslationDeletedEvent>,
        $StreamProvider<TranslationDeletedEvent> {
  const TranslationDeletedEventsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'translationDeletedEventsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$translationDeletedEventsHash();

  @$internal
  @override
  $StreamProviderElement<TranslationDeletedEvent> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<TranslationDeletedEvent> create(Ref ref) {
    return translationDeletedEvents(ref);
  }
}

String _$translationDeletedEventsHash() =>
    r'01239eac8d9901838e5274277f35efe8aa65ad8f';

@ProviderFor(translationStatusChangedEvents)
const translationStatusChangedEventsProvider =
    TranslationStatusChangedEventsProvider._();

final class TranslationStatusChangedEventsProvider
    extends
        $FunctionalProvider<
          AsyncValue<TranslationStatusChangedEvent>,
          TranslationStatusChangedEvent,
          Stream<TranslationStatusChangedEvent>
        >
    with
        $FutureModifier<TranslationStatusChangedEvent>,
        $StreamProvider<TranslationStatusChangedEvent> {
  const TranslationStatusChangedEventsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'translationStatusChangedEventsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$translationStatusChangedEventsHash();

  @$internal
  @override
  $StreamProviderElement<TranslationStatusChangedEvent> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<TranslationStatusChangedEvent> create(Ref ref) {
    return translationStatusChangedEvents(ref);
  }
}

String _$translationStatusChangedEventsHash() =>
    r'301fe34f4d557bcf755d84efdad5a0173d7b33cc';

@ProviderFor(projectCreatedEvents)
const projectCreatedEventsProvider = ProjectCreatedEventsProvider._();

final class ProjectCreatedEventsProvider
    extends
        $FunctionalProvider<
          AsyncValue<ProjectCreatedEvent>,
          ProjectCreatedEvent,
          Stream<ProjectCreatedEvent>
        >
    with
        $FutureModifier<ProjectCreatedEvent>,
        $StreamProvider<ProjectCreatedEvent> {
  const ProjectCreatedEventsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'projectCreatedEventsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$projectCreatedEventsHash();

  @$internal
  @override
  $StreamProviderElement<ProjectCreatedEvent> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<ProjectCreatedEvent> create(Ref ref) {
    return projectCreatedEvents(ref);
  }
}

String _$projectCreatedEventsHash() =>
    r'543d9871c7bf3d7e0763b4b06a74120697eba59b';

@ProviderFor(projectUpdatedEvents)
const projectUpdatedEventsProvider = ProjectUpdatedEventsProvider._();

final class ProjectUpdatedEventsProvider
    extends
        $FunctionalProvider<
          AsyncValue<ProjectUpdatedEvent>,
          ProjectUpdatedEvent,
          Stream<ProjectUpdatedEvent>
        >
    with
        $FutureModifier<ProjectUpdatedEvent>,
        $StreamProvider<ProjectUpdatedEvent> {
  const ProjectUpdatedEventsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'projectUpdatedEventsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$projectUpdatedEventsHash();

  @$internal
  @override
  $StreamProviderElement<ProjectUpdatedEvent> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<ProjectUpdatedEvent> create(Ref ref) {
    return projectUpdatedEvents(ref);
  }
}

String _$projectUpdatedEventsHash() =>
    r'21aa3c8fa854c0e2efa7c5266661fdc5bf2faab9';

@ProviderFor(projectCompletedEvents)
const projectCompletedEventsProvider = ProjectCompletedEventsProvider._();

final class ProjectCompletedEventsProvider
    extends
        $FunctionalProvider<
          AsyncValue<ProjectCompletedEvent>,
          ProjectCompletedEvent,
          Stream<ProjectCompletedEvent>
        >
    with
        $FutureModifier<ProjectCompletedEvent>,
        $StreamProvider<ProjectCompletedEvent> {
  const ProjectCompletedEventsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'projectCompletedEventsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$projectCompletedEventsHash();

  @$internal
  @override
  $StreamProviderElement<ProjectCompletedEvent> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<ProjectCompletedEvent> create(Ref ref) {
    return projectCompletedEvents(ref);
  }
}

String _$projectCompletedEventsHash() =>
    r'448cdfdbb8024fa5f7ca23c6050dd0b4e03e5d80';

@ProviderFor(translationAddedToTmEvents)
const translationAddedToTmEventsProvider =
    TranslationAddedToTmEventsProvider._();

final class TranslationAddedToTmEventsProvider
    extends
        $FunctionalProvider<
          AsyncValue<TranslationAddedToTmEvent>,
          TranslationAddedToTmEvent,
          Stream<TranslationAddedToTmEvent>
        >
    with
        $FutureModifier<TranslationAddedToTmEvent>,
        $StreamProvider<TranslationAddedToTmEvent> {
  const TranslationAddedToTmEventsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'translationAddedToTmEventsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$translationAddedToTmEventsHash();

  @$internal
  @override
  $StreamProviderElement<TranslationAddedToTmEvent> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<TranslationAddedToTmEvent> create(Ref ref) {
    return translationAddedToTmEvents(ref);
  }
}

String _$translationAddedToTmEventsHash() =>
    r'bc6c819679582704342599f5397d532780c6fcab';

/// Get progress events for a specific batch

@ProviderFor(batchProgressForBatch)
const batchProgressForBatchProvider = BatchProgressForBatchFamily._();

/// Get progress events for a specific batch

final class BatchProgressForBatchProvider
    extends
        $FunctionalProvider<
          AsyncValue<BatchProgressEvent>,
          BatchProgressEvent,
          Stream<BatchProgressEvent>
        >
    with
        $FutureModifier<BatchProgressEvent>,
        $StreamProvider<BatchProgressEvent> {
  /// Get progress events for a specific batch
  const BatchProgressForBatchProvider._({
    required BatchProgressForBatchFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'batchProgressForBatchProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$batchProgressForBatchHash();

  @override
  String toString() {
    return r'batchProgressForBatchProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<BatchProgressEvent> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<BatchProgressEvent> create(Ref ref) {
    final argument = this.argument as String;
    return batchProgressForBatch(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is BatchProgressForBatchProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$batchProgressForBatchHash() =>
    r'6f6ca85e280403697ffff057937bebd1acb40e91';

/// Get progress events for a specific batch

final class BatchProgressForBatchFamily extends $Family
    with $FunctionalFamilyOverride<Stream<BatchProgressEvent>, String> {
  const BatchProgressForBatchFamily._()
    : super(
        retry: null,
        name: r'batchProgressForBatchProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Get progress events for a specific batch

  BatchProgressForBatchProvider call(String batchId) =>
      BatchProgressForBatchProvider._(argument: batchId, from: this);

  @override
  String toString() => r'batchProgressForBatchProvider';
}

/// Get completion events for a specific batch

@ProviderFor(batchCompletedForBatch)
const batchCompletedForBatchProvider = BatchCompletedForBatchFamily._();

/// Get completion events for a specific batch

final class BatchCompletedForBatchProvider
    extends
        $FunctionalProvider<
          AsyncValue<BatchCompletedEvent>,
          BatchCompletedEvent,
          Stream<BatchCompletedEvent>
        >
    with
        $FutureModifier<BatchCompletedEvent>,
        $StreamProvider<BatchCompletedEvent> {
  /// Get completion events for a specific batch
  const BatchCompletedForBatchProvider._({
    required BatchCompletedForBatchFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'batchCompletedForBatchProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$batchCompletedForBatchHash();

  @override
  String toString() {
    return r'batchCompletedForBatchProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<BatchCompletedEvent> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<BatchCompletedEvent> create(Ref ref) {
    final argument = this.argument as String;
    return batchCompletedForBatch(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is BatchCompletedForBatchProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$batchCompletedForBatchHash() =>
    r'cf3fd70fcca24957e8bafc52e04349121edecc3c';

/// Get completion events for a specific batch

final class BatchCompletedForBatchFamily extends $Family
    with $FunctionalFamilyOverride<Stream<BatchCompletedEvent>, String> {
  const BatchCompletedForBatchFamily._()
    : super(
        retry: null,
        name: r'batchCompletedForBatchProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Get completion events for a specific batch

  BatchCompletedForBatchProvider call(String batchId) =>
      BatchCompletedForBatchProvider._(argument: batchId, from: this);

  @override
  String toString() => r'batchCompletedForBatchProvider';
}

/// Get failure events for a specific batch

@ProviderFor(batchFailedForBatch)
const batchFailedForBatchProvider = BatchFailedForBatchFamily._();

/// Get failure events for a specific batch

final class BatchFailedForBatchProvider
    extends
        $FunctionalProvider<
          AsyncValue<BatchFailedEvent>,
          BatchFailedEvent,
          Stream<BatchFailedEvent>
        >
    with $FutureModifier<BatchFailedEvent>, $StreamProvider<BatchFailedEvent> {
  /// Get failure events for a specific batch
  const BatchFailedForBatchProvider._({
    required BatchFailedForBatchFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'batchFailedForBatchProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$batchFailedForBatchHash();

  @override
  String toString() {
    return r'batchFailedForBatchProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<BatchFailedEvent> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<BatchFailedEvent> create(Ref ref) {
    final argument = this.argument as String;
    return batchFailedForBatch(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is BatchFailedForBatchProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$batchFailedForBatchHash() =>
    r'b29a19d6827380338dfe262fed4fe5b12bbddef9';

/// Get failure events for a specific batch

final class BatchFailedForBatchFamily extends $Family
    with $FunctionalFamilyOverride<Stream<BatchFailedEvent>, String> {
  const BatchFailedForBatchFamily._()
    : super(
        retry: null,
        name: r'batchFailedForBatchProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Get failure events for a specific batch

  BatchFailedForBatchProvider call(String batchId) =>
      BatchFailedForBatchProvider._(argument: batchId, from: this);

  @override
  String toString() => r'batchFailedForBatchProvider';
}

/// Get all events for a specific project

@ProviderFor(projectEvents)
const projectEventsProvider = ProjectEventsFamily._();

/// Get all events for a specific project

final class ProjectEventsProvider
    extends
        $FunctionalProvider<
          AsyncValue<ProjectEvent>,
          ProjectEvent,
          Stream<ProjectEvent>
        >
    with $FutureModifier<ProjectEvent>, $StreamProvider<ProjectEvent> {
  /// Get all events for a specific project
  const ProjectEventsProvider._({
    required ProjectEventsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'projectEventsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$projectEventsHash();

  @override
  String toString() {
    return r'projectEventsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<ProjectEvent> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<ProjectEvent> create(Ref ref) {
    final argument = this.argument as String;
    return projectEvents(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ProjectEventsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$projectEventsHash() => r'52100e15ddc23f91601f21d50ed5cca0d0b82a34';

/// Get all events for a specific project

final class ProjectEventsFamily extends $Family
    with $FunctionalFamilyOverride<Stream<ProjectEvent>, String> {
  const ProjectEventsFamily._()
    : super(
        retry: null,
        name: r'projectEventsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Get all events for a specific project

  ProjectEventsProvider call(String projectId) =>
      ProjectEventsProvider._(argument: projectId, from: this);

  @override
  String toString() => r'projectEventsProvider';
}
