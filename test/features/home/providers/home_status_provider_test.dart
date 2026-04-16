import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/home/providers/action_grid_providers.dart';
import 'package:twmt/features/home/providers/home_status_provider.dart';
import 'package:twmt/features/home/providers/workflow_providers.dart';

import '../../../helpers/test_bootstrap.dart';

void main() {
  setUp(() async => TestBootstrap.registerFakes());

  ProviderContainer containerWith({
    required int toReview,
    required int ready,
    required int updates,
  }) {
    return ProviderContainer(overrides: [
      projectsToReviewCountProvider.overrideWith((ref) async => toReview),
      projectsReadyToCompileCountProvider.overrideWith((ref) async => ready),
      modsWithUpdatesCountProvider.overrideWith((ref) async => updates),
    ]);
  }

  test('needsAttention wins over everything', () async {
    final c = containerWith(toReview: 3, ready: 5, updates: 10);
    addTearDown(c.dispose);
    final s = await c.read(homeStatusProvider.future);
    expect(s.kind, HomeStatusKind.needsAttention);
    expect(s.count, 3);
    expect(s.label, '3 projects need your attention');
  });

  test('readyToCompile wins when no review', () async {
    final c = containerWith(toReview: 0, ready: 2, updates: 10);
    addTearDown(c.dispose);
    final s = await c.read(homeStatusProvider.future);
    expect(s.kind, HomeStatusKind.readyToCompile);
    expect(s.count, 2);
  });

  test('modUpdates wins when no review or ready', () async {
    final c = containerWith(toReview: 0, ready: 0, updates: 5);
    addTearDown(c.dispose);
    final s = await c.read(homeStatusProvider.future);
    expect(s.kind, HomeStatusKind.modUpdates);
    expect(s.count, 5);
  });

  test('allCaughtUp fallback', () async {
    final c = containerWith(toReview: 0, ready: 0, updates: 0);
    addTearDown(c.dispose);
    final s = await c.read(homeStatusProvider.future);
    expect(s.kind, HomeStatusKind.allCaughtUp);
    expect(s.label, 'All caught up');
  });

  test('singular/plural wording', () async {
    final c = containerWith(toReview: 1, ready: 0, updates: 0);
    addTearDown(c.dispose);
    final s = await c.read(homeStatusProvider.future);
    expect(s.label, '1 project need your attention');
  });
}
