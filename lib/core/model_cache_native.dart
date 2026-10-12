import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'model_assets.dart';

ModelCache createModelCache() => FileModelCache();

class FileModelCache implements ModelCache {
  final Directory? directoryOverride;
  FileModelCache({this.directoryOverride});
  Future<Directory> get directory async =>
      (directoryOverride ??
              Directory(
                '${(await getTemporaryDirectory()).path}/pulse-model-v1',
              ))
          .create(recursive: true);
  Future<File> file(String key) async => File('${(await directory).path}/$key');
  @override
  Future<Uint8List?> read(String key) async {
    final f = await file(key);
    return await f.exists() ? f.readAsBytes() : null;
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    final f = await file(key);
    final partial = File(
      '${f.path}.${DateTime.now().microsecondsSinceEpoch}.partial',
    );
    try {
      await partial.writeAsBytes(bytes, flush: true);
      await partial.rename(f.path);
    } finally {
      try {
        if (await partial.exists()) await partial.delete();
      } catch (_) {
        /* Preserve the original storage failure. */
      }
    }
  }

  @override
  Future<ModelLocation> location(String key, Uint8List bytes) async {
    final cached = await file(key);
    final expected =
        RegExp(r'-([0-9a-f]{64})\.glb$').firstMatch(key)?.group(1) ??
        sha256.convert(bytes).toString();
    try {
      if (await cached.exists() &&
          await cached.length() == bytes.length &&
          (await sha256.bind(cached.openRead()).first).toString() == expected) {
        return ModelLocation(cached.uri.toString());
      }
    } catch (_) {
      /* An unreadable or corrupt cache is never a playback source. */
    }
    // If an atomic cache write failed, try an independently owned playback file.
    final temporary = File(
      '${cached.path}.${DateTime.now().microsecondsSinceEpoch}.glb',
    );
    try {
      await temporary.writeAsBytes(bytes, flush: true);
    } catch (_) {
      try {
        if (await temporary.exists()) await temporary.delete();
      } catch (_) {
        /* Preserve the original storage failure. */
      }
      rethrow;
    }
    return ModelLocation(temporary.uri.toString(), () {
      temporary.delete().catchError((Object _) => temporary);
    });
  }

  @override
  Future<void> remove(String key) async {
    final f = await file(key);
    if (await f.exists()) await f.delete();
  }

  @override
  Future<void> clear() async {
    final dir = await directory;
    await dir.delete(recursive: true);
  }
}
