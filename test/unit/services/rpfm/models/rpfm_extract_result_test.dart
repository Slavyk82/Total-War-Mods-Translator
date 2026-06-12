import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/rpfm/models/rpfm_extract_result.dart';

RpfmExtractResult _result() => RpfmExtractResult(
      packFilePath: 'C:/mods/x.pack',
      outputDirectory: 'C:/tmp/extract',
      extractedFiles: const ['text/db/a.loc', 'text/db/b.loc'],
      localizationFileCount: 2,
      totalSizeBytes: 2048,
      durationMs: 300,
      timestamp: DateTime(2026, 1, 1),
      warnings: const ['minor'],
    );

void main() {
  test('copyWith overrides only the targeted field', () {
    final r = _result();
    expect(r.copyWith(durationMs: 999).durationMs, 999);
    expect(r.copyWith(durationMs: 999).packFilePath, 'C:/mods/x.pack');
  });

  test('value equality + hashCode', () {
    final a = _result();
    expect(a, equals(a.copyWith()));
    expect(a.hashCode, a.copyWith().hashCode);
  });

  test('json round-trip', () {
    final restored = RpfmExtractResult.fromJson(_result().toJson());
    expect(restored.packFilePath, 'C:/mods/x.pack');
    expect(restored.extractedFiles, ['text/db/a.loc', 'text/db/b.loc']);
    expect(restored.localizationFileCount, 2);
    expect(restored.warnings, ['minor']);
  });

  test('toString summarizes the extraction', () {
    expect(_result().toString(), contains('locFiles: 2'));
  });
}
