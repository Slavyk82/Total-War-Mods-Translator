import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/steam/models/steam_exceptions.dart';
import 'package:twmt/services/steam/models/workshop_publish_params.dart';
import 'package:twmt/services/steam/vdf_generator.dart';

void main() {
  late Directory tempRoot;
  late Directory contentDir;
  late File previewFile;
  late VdfGenerator generator;

  setUp(() async {
    generator = VdfGenerator();
    tempRoot = await Directory.systemTemp.createTemp('vdf_gen_test_');
    contentDir = Directory('${tempRoot.path}/content')..createSync();
    File('${contentDir.path}/mod.pack').writeAsStringSync('PACKDATA');
    previewFile = File('${tempRoot.path}/preview.png')..writeAsStringSync('img');
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  WorkshopPublishParams params({
    String? contentFolder,
    String? previewPath,
    String title = 'My Mod',
    String description = 'A description',
    String changeNote = '',
    List<String> tags = const [],
    WorkshopVisibility visibility = WorkshopVisibility.public_,
    String publishedFileId = '0',
  }) {
    return WorkshopPublishParams(
      appId: '1142710',
      publishedFileId: publishedFileId,
      contentFolder: contentFolder ?? contentDir.path,
      previewFile: previewPath ?? previewFile.path,
      title: title,
      description: description,
      changeNote: changeNote,
      visibility: visibility,
      tags: tags,
    );
  }

  String errMessage(Result<String, SteamServiceException> result) {
    return (result as Err<String, SteamServiceException>).error.message;
  }

  group('VdfGenerator.generateVdf - validation', () {
    test('fails when content folder does not exist', () async {
      final result = await generator.generateVdf(
        params(contentFolder: '${tempRoot.path}/nope'),
      );
      expect(result, isA<Err>());
      expect(errMessage(result), contains('Content folder does not exist'));
    });

    test('fails when content folder has no .pack file', () async {
      final empty = Directory('${tempRoot.path}/empty')..createSync();
      final result = await generator.generateVdf(
        params(contentFolder: empty.path),
      );
      expect(errMessage(result), contains('does not contain a .pack file'));
    });

    test('fails when preview file does not exist', () async {
      final result = await generator.generateVdf(
        params(previewPath: '${tempRoot.path}/missing.png'),
      );
      expect(errMessage(result), contains('Preview file does not exist'));
    });

    test('fails when preview file exceeds 1MB', () async {
      final big = File('${tempRoot.path}/big.png')
        ..writeAsBytesSync(List.filled(1024 * 1024 + 1, 0));
      final result = await generator.generateVdf(
        params(previewPath: big.path),
      );
      expect(errMessage(result), contains('exceeds 1MB limit'));
    });

    test('fails when title is blank', () async {
      final result = await generator.generateVdf(params(title: '   '));
      expect(errMessage(result), contains('Title cannot be empty'));
    });
  });

  group('VdfGenerator.generateVdf - content', () {
    test('writes a valid VDF file to the requested output dir', () async {
      final outDir = Directory('${tempRoot.path}/out')..createSync();
      final result = await generator.generateVdf(
        params(
          title: 'Cool Mod',
          description: 'Desc',
          visibility: WorkshopVisibility.friendsOnly,
          publishedFileId: '12345',
        ),
        outputDir: outDir.path,
      );

      expect(result, isA<Ok>());
      final vdfPath = (result as Ok<String, SteamServiceException>).value;
      expect(vdfPath, startsWith(outDir.path));
      expect(File(vdfPath).existsSync(), isTrue);

      final content = File(vdfPath).readAsStringSync();
      expect(content, contains('"workshopitem"'));
      expect(content, contains('"appid"           "1142710"'));
      expect(content, contains('"publishedfileid" "12345"'));
      expect(content, contains('"title"           "Cool Mod"'));
      // friendsOnly -> value 1
      expect(content, contains('"visibility"      "1"'));
      // No tags block when tags are empty.
      expect(content, isNot(contains('"tags"')));
    });

    test('emits a tags block with indexed entries', () async {
      final outDir = Directory('${tempRoot.path}/out')..createSync();
      final result = await generator.generateVdf(
        params(tags: ['Units', 'Overhaul']),
        outputDir: outDir.path,
      );

      final content = File((result as Ok).value).readAsStringSync();
      expect(content, contains('"tags"'));
      expect(content, contains('"0"    "Units"'));
      expect(content, contains('"1"    "Overhaul"'));
    });

    test('escapes backslashes and quotes and strips carriage returns',
        () async {
      final outDir = Directory('${tempRoot.path}/out')..createSync();
      final result = await generator.generateVdf(
        params(
          title: r'Path\To "Mod"',
          description: 'line1\r\nline2',
        ),
        outputDir: outDir.path,
      );

      final content = File((result as Ok).value).readAsStringSync();
      expect(content, contains(r'"title"           "Path\\To \"Mod\""'));
      // \r removed but \n kept inside the description value.
      expect(content, contains('"description"     "line1\nline2"'));
      expect(content, isNot(contains('\r')));
    });
  });
}
