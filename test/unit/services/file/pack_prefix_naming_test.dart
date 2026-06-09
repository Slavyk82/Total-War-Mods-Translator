import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/file/pack_export_utils.dart';
import 'package:twmt/services/file/loc_file_service_impl.dart';

import '../../../helpers/noop_logger.dart';

void main() {
  late PackExportUtils utils;

  setUp(() {
    utils = PackExportUtils(logger: NoopLogger());
  });

  group('buildPackFileName', () {
    test('uses the default prefix when none is provided', () {
      final name = utils.buildPackFileName('FR', r'C:\mods\Cool.pack');
      expect(name, '!!!!!!!!!!_fr_twmt_cool.pack');
    });

    test('uses a custom prefix when provided', () {
      final name = utils.buildPackFileName(
        'FR',
        r'C:\mods\Cool.pack',
        prefix: 'zzz_',
      );
      expect(name, 'zzz__fr_twmt_cool.pack');
    });

    test('applies the custom prefix to game-translation packs', () {
      final name = utils.buildPackFileName(
        'fr',
        r'C:\game\local_en.pack',
        prefix: 'zzz_',
      );
      expect(name, 'zzz__fr_twmt_game_translation.pack');
    });
  });

  group('buildLocInternalPath', () {
    test('uses the default prefix when none is provided', () {
      final p = LocFileServiceImpl.buildLocInternalPath(
        'text/db/Something.loc',
        'fr',
      );
      expect(p, 'text/db/!!!!!!!!!!_fr_twmt_something.loc');
    });

    test('uses a custom prefix when provided', () {
      final p = LocFileServiceImpl.buildLocInternalPath(
        'text/db/Something.loc',
        'fr',
        prefix: 'zzz',
      );
      expect(p, 'text/db/zzz_fr_twmt_something.loc');
    });

    test('handles a flat path with no directory', () {
      final p = LocFileServiceImpl.buildLocInternalPath(
        'Something.loc',
        'fr',
        prefix: 'zzz',
      );
      expect(p, 'zzz_fr_twmt_something.loc');
    });
  });
}
