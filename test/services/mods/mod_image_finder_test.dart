import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/mods/utils/mod_image_finder.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mod_image_test_');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  void writeFile(String name) => File('${dir.path}/$name').writeAsStringSync('x');

  test('returns null when no image is present', () async {
    writeFile('mod.pack');
    expect(await ModImageFinder.findModImage(dir, 'mod'), isNull);
  });

  test('prefers an image named after the pack file', () async {
    writeFile('mod.png');
    writeFile('preview.png');
    final result = await ModImageFinder.findModImage(dir, 'mod');
    expect(result, endsWith('mod.png'));
  });

  test('honours the extension priority (jpg before png) for the pack name',
      () async {
    writeFile('mod.jpg');
    writeFile('mod.png');
    final result = await ModImageFinder.findModImage(dir, 'mod');
    expect(result, endsWith('mod.jpg'));
  });

  test('falls back to preview.* when no pack-named image exists', () async {
    writeFile('preview.jpeg');
    writeFile('screenshot.png');
    final result = await ModImageFinder.findModImage(dir, 'mod');
    expect(result, endsWith('preview.jpeg'));
  });

  test('falls back to any image file as a last resort', () async {
    writeFile('random_screenshot.png');
    final result = await ModImageFinder.findModImage(dir, 'mod');
    expect(result, endsWith('random_screenshot.png'));
  });
}
