import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'model_assets.dart';

ModelCache createModelCache() => _BrowserCache();

class _BrowserCache implements ModelCache {
  Future<web.Cache> get cache =>
      web.window.caches.open('pulse-model-v1').toDart;
  String url(String key) =>
      Uri.base.resolve('__pulse_model_cache__/$key').toString();
  @override
  Future<Uint8List?> read(String key) async {
    final response = await (await cache).match(url(key).toJS).toDart;
    return response == null
        ? null
        : (await response.arrayBuffer().toDart).toDart.asUint8List();
  }

  @override
  Future<void> write(String key, Uint8List bytes) async =>
      (await cache).put(url(key).toJS, web.Response(bytes.toJS)).toDart;
  @override
  Future<void> remove(String key) async {
    await (await cache).delete(url(key).toJS).toDart;
  }

  @override
  Future<void> clear() async {
    await web.window.caches.delete('pulse-model-v1').toDart;
  }

  @override
  Future<ModelLocation> location(String key, Uint8List bytes) async {
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'model/gltf-binary'),
    );
    final source = web.URL.createObjectURL(blob);
    return ModelLocation(source, () => web.URL.revokeObjectURL(source));
  }
}
