import 'dart:typed_data';

import 'model_assets.dart';

ModelCache createModelCache() => _MemoryCache();

class _MemoryCache implements ModelCache {
  final data = <String, Uint8List>{};
  @override
  Future<Uint8List?> read(String key) async => data[key];
  @override
  Future<void> write(String key, Uint8List bytes) async {
    data[key] = bytes;
  }

  @override
  Future<void> remove(String key) async {
    data.remove(key);
  }

  @override
  Future<void> clear() async => data.clear();
  @override
  Future<ModelLocation> location(String key, Uint8List bytes) async =>
      throw UnsupportedError('model display');
}
