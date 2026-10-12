import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:share_plus/share_plus.dart';

Future<bool> exportBackupFile(String json, String filename, Rect origin) async {
  final result = await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile.fromData(
          Uint8List.fromList(utf8.encode(json)),
          mimeType: 'application/json',
          name: filename,
        ),
      ],
      fileNameOverrides: [filename],
      subject: 'PULSE 手动备份',
      sharePositionOrigin: origin,
    ),
  );
  if (result.status == ShareResultStatus.unavailable) {
    throw StateError('系统分享暂不可用，请使用复制完整备份。');
  }
  return result.status != ShareResultStatus.dismissed;
}
