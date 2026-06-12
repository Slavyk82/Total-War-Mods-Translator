import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'import_graph.dart';

/// Known, intentionally-tolerated violations. EACH entry must be removed by
/// the lot that fixes it. Format: '<importerLibPath> -> <importedLibPath>'.
/// The allowlist shrinks to empty; do NOT add new entries.
const _allowlist = <String>{
  // === Seeded in Lot 0 (run with TWMT_PRINT_VIOLATIONS=1 to regenerate) ===
  'lib/services/translation/headless_batch_translation_runner.dart -> lib/providers/shared/service_providers.dart', // lot:3
  'lib/services/translation/headless_batch_translation_runner.dart -> lib/providers/translation_settings_provider.dart', // lot:3 (service→Riverpod leak; target relocated by provider-promotion lot)
  'lib/services/translation/headless_validation_rescan_service.dart -> lib/providers/shared/repository_providers.dart', // lot:3
  'lib/services/translation/headless_validation_rescan_service.dart -> lib/providers/shared/service_providers.dart', // lot:3
};

/// Paths that LOOK like Riverpod providers but are not (service purity rule).
bool _isProviderFalsePositive(String libPath) =>
    libPath.startsWith('lib/services/llm/providers/') ||
    libPath.startsWith('lib/services/database/migrations/') ||
    libPath == 'lib/repositories/translation_provider_repository.dart';

String _featureOf(String libPath) {
  const prefix = 'lib/features/';
  if (!libPath.startsWith(prefix)) return '';
  return libPath.substring(prefix.length).split('/').first;
}

bool _isRiverpodProviderImport(String importedLibPath) {
  if (_isProviderFalsePositive(importedLibPath)) return false;
  return importedLibPath.contains('/providers/') ||
      importedLibPath.endsWith('_provider.dart') ||
      importedLibPath.endsWith('_providers.dart');
}

void main() {
  final libDir = Directory('lib');
  final files = libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.endsWith('.g.dart'))
      .where((f) => !f.path.endsWith('.freezed.dart'))
      .map((f) => f.path.replaceAll(r'\', '/'))
      .toList();

  final violations = <String>[];

  for (final libRel in files) {
    final imports = importsOf(libRel, libRel);
    for (final target in imports) {
      final srcF = _featureOf(libRel);
      final tgtF = _featureOf(target);
      if (srcF.isNotEmpty && tgtF.isNotEmpty && srcF != tgtF) {
        violations.add('$libRel -> $target');
        continue;
      }
      if (libRel.startsWith('lib/services/') &&
          _isRiverpodProviderImport(target)) {
        violations.add('$libRel -> $target');
        continue;
      }
      if (libRel.startsWith('lib/models/') &&
          !(target.startsWith('lib/models/'))) {
        violations.add('$libRel -> $target');
        continue;
      }
      if (libRel.startsWith('lib/widgets/') && tgtF.isNotEmpty) {
        violations.add('$libRel -> $target');
        continue;
      }
    }
  }

  if (Platform.environment['TWMT_PRINT_VIOLATIONS'] == '1') {
    for (final v in violations..sort()) {
      // ignore: avoid_print
      print("  '$v',");
    }
  }

  test('no import-boundary violations outside the allowlist', () {
    final unexpected =
        violations.where((v) => !_allowlist.contains(v)).toList()..sort();
    expect(
      unexpected,
      isEmpty,
      reason: 'New layering violations introduced:\n${unexpected.join('\n')}\n'
          'Fix the import (promote shared code to a global layer or inject '
          'via constructor) — do not add to the allowlist.',
    );
  });

  test('allowlist has no stale entries', () {
    final stale = _allowlist.where((v) => !violations.contains(v)).toList()
      ..sort();
    expect(
      stale,
      isEmpty,
      reason: 'Allowlist entries no longer violate — delete them:\n'
          '${stale.join('\n')}',
    );
  });
}
