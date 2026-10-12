import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_fitness/core/model_cache_native.dart';

void main() {
  late Directory directory;
  final bytes = Uint8List.fromList([103, 108, 84, 70, 4, 5]);
  final key = 'row-${sha256.convert(bytes)}.glb';
  setUp(
    () async =>
        directory = await Directory.systemTemp.createTemp('pulse-cache-test-'),
  );
  tearDown(() async => directory.delete(recursive: true));
  test('a corrupted existing file cannot be returned after failed cache replacement', () async {
    await File('${directory.path}/$key').writeAsBytes([0, 1, 2, 3, 4, 5]);
    final cache = FileModelCache(directoryOverride: directory);
    final location = await cache.location(key, bytes);
    final playback = File.fromUri(Uri.parse(location.src));
    expect(await playback.readAsBytes(), bytes);
    expect(playback.path, isNot('${directory.path}/$key'));
    location.release();
    location.release();
  });
  test('failed atomic replacement removes its partial file', () async {
    await Directory('${directory.path}/$key').create();
    final cache = FileModelCache(directoryOverride: directory);
    await expectLater(
      cache.write(key, bytes),
      throwsA(isA<FileSystemException>()),
    );
    expect(
      (await directory.list().toList()).where(
        (f) => f.path.endsWith('.partial'),
      ),
      isEmpty,
    );
  });
}
