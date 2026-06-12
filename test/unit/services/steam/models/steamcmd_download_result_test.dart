import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/steam/models/steamcmd_download_result.dart';

SteamCmdDownloadResult _result() => SteamCmdDownloadResult(
      workshopId: '123',
      appId: 1142710,
      downloadPath: 'C:/mods/123',
      modTitle: 'Cool Mod',
      sizeBytes: 4096,
      durationMs: 1500,
      timestamp: DateTime(2026, 1, 1),
      wasUpdate: true,
      downloadedFiles: const ['a.pack'],
    );

void main() {
  test('copyWith overrides only the targeted field', () {
    final r = _result();
    expect(r.copyWith(sizeBytes: 99).sizeBytes, 99);
    expect(r.copyWith(sizeBytes: 99).workshopId, '123');
  });

  test('value equality + hashCode', () {
    expect(_result(), equals(_result()));
    expect(_result().hashCode, _result().hashCode);
  });

  test('json round-trip', () {
    final restored = SteamCmdDownloadResult.fromJson(_result().toJson());
    expect(restored.workshopId, '123');
    expect(restored.appId, 1142710);
    expect(restored.wasUpdate, isTrue);
    expect(restored.downloadedFiles, ['a.pack']);
  });

  test('defaults: wasUpdate false when omitted', () {
    final r = SteamCmdDownloadResult(
      workshopId: '1',
      appId: 1,
      downloadPath: 'p',
      sizeBytes: 0,
      durationMs: 0,
      timestamp: DateTime(2026, 1, 1),
    );
    expect(r.wasUpdate, isFalse);
    expect(r.modTitle, isNull);
  });
}
