import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_fitness/core/backup_export_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const share = MethodChannel('dev.fluttercommunity.plus/share');
  const path = MethodChannel('plugins.flutter.io/path_provider');
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'pulse-backup-export-test-',
    );
    messenger.setMockMethodCallHandler(path, (call) async => directory.path);
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(path, null);
    messenger.setMockMethodCallHandler(share, null);
    await directory.delete(recursive: true);
  });
  test('native sharing writes correct JSON filename and iPad origin', () async {
    messenger.setMockMethodCallHandler(share, (call) async {
      expect(call.method, 'share');
      final args = call.arguments as Map;
      final filename = (args['paths'] as List).single as String;
      expect(filename.endsWith('/pulse-backup.json'), true);
      expect(await File(filename).readAsString(), '{"name":"记录"}');
      expect(args['mimeTypes'], ['application/json']);
      expect(args['originWidth'], 150.0);
      expect(args['originHeight'], 50.0);
      return 'com.apple.UIKit.activity.SaveToFiles';
    });
    expect(
      await exportBackupFile(
        '{"name":"记录"}',
        'pulse-backup.json',
        const Rect.fromLTWH(10, 20, 150, 50),
      ),
      true,
    );
  });
  test('native share cancellation is not reported as saved', () async {
    messenger.setMockMethodCallHandler(share, (call) async => '');
    expect(
      await exportBackupFile(
        '{}',
        'backup.json',
        const Rect.fromLTWH(0, 0, 1, 1),
      ),
      false,
    );
  });
  test(
    'unavailable native share tells caller to use another export path',
    () async {
      messenger.setMockMethodCallHandler(
        share,
        (call) async => 'dev.fluttercommunity.plus/share/unavailable',
      );
      await expectLater(
        exportBackupFile('{}', 'backup.json', const Rect.fromLTWH(0, 0, 1, 1)),
        throwsStateError,
      );
    },
  );
}
