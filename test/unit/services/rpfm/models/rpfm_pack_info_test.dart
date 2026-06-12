import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/rpfm/models/rpfm_pack_info.dart';

RpfmPackInfo _info() => RpfmPackInfo(
      packFilePath: 'C:/mods/x.pack',
      fileName: 'x.pack',
      sizeBytes: 2 * 1024 * 1024,
      fileCount: 20,
      localizationFileCount: 3,
      formatVersion: 3,
      lastModified: DateTime(2026, 1, 1),
    );

void main() {
  test('sizeMB converts bytes to megabytes', () {
    expect(_info().sizeMB, 2.0);
  });

  test('copyWith overrides only the targeted field', () {
    final i = _info();
    expect(i.copyWith(fileCount: 99).fileCount, 99);
    expect(i.copyWith(fileCount: 99).fileName, 'x.pack');
  });

  test('value equality + hashCode', () {
    expect(_info(), equals(_info()));
    expect(_info().hashCode, _info().hashCode);
  });

  test('json round-trip', () {
    final restored = RpfmPackInfo.fromJson(_info().toJson());
    expect(restored.fileName, 'x.pack');
    expect(restored.fileCount, 20);
    expect(restored.localizationFileCount, 3);
    expect(restored.formatVersion, 3);
  });
}
