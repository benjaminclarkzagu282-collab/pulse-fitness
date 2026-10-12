import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pulse_fitness/core/model_assets.dart';

class MemoryCache implements ModelCache {
  final values = <String, Uint8List>{};
  @override
  Future<Uint8List?> read(String key) async => values[key];
  @override
  Future<void> write(String key, Uint8List bytes) async => values[key] = bytes;
  @override
  Future<void> remove(String key) async => values.remove(key);
  @override
  Future<void> clear() async => values.clear();
  @override
  Future<ModelLocation> location(String key, Uint8List bytes) async =>
      ModelLocation('memory:$key');
}

class UnavailableCache extends MemoryCache {
  @override
  Future<Uint8List?> read(String key) async => throw StateError('unavailable');
  @override
  Future<void> write(String key, Uint8List bytes) async =>
      throw StateError('quota');
}

void main() {
  final raw = Uint8List.fromList([
    103,
    108,
    84,
    70,
    ...List.generate(1024, (i) => i % 256),
  ]);
  final packed = Uint8List.fromList(GZipEncoder().encode(raw)!);
  ModelAsset entry({bool bundled = false}) => ModelAsset(
    id: 'row',
    bytes: raw.length,
    compressedBytes: packed.length,
    sha256Hex: sha256.convert(raw).toString(),
    compressedSha256: sha256.convert(packed).toString(),
    bundled: bundled,
  );
  test(
    'verified download is reused without a second network request',
    () async {
      final cache = MemoryCache();
      var requests = 0;
      final store = ModelAssets(
        manifest: {'row': entry()},
        cache: cache,
        baseUri: Uri.parse('https://example.test/'),
        clientFactory: () => MockClient((request) async {
          requests++;
          expect(request.url.path, '/remote/models/athlete_row.glb.gz');
          return http.Response.bytes(packed, 200);
        }),
      );
      await store.resolve('row');
      await store.resolve('row');
      expect(requests, 1);
      expect(cache.values.values.single, raw);
    },
  );
  test('a corrupted download is rejected and never enters the cache', () async {
    final cache = MemoryCache();
    final store = ModelAssets(
      manifest: {'row': entry()},
      cache: cache,
      baseUri: Uri.parse('https://example.test/'),
      clientFactory: () =>
          MockClient((_) async => http.Response.bytes([1, 2, 3], 200)),
    );
    await expectLater(
      store.resolve('row'),
      throwsA(isA<ModelAssetException>()),
    );
    expect(cache.values, isEmpty);
  });
  test('corrupted cached bytes are discarded and fetched again', () async {
    final cache = MemoryCache()
      ..values[entry().cacheKey] = Uint8List.fromList([0]);
    final store = ModelAssets(
      manifest: {'row': entry()},
      cache: cache,
      baseUri: Uri.parse('https://example.test/'),
      clientFactory: () =>
          MockClient((_) async => http.Response.bytes(packed, 200)),
    );
    await store.resolve('row');
    expect(cache.values.values.single, raw);
  });
  test(
    'bundled action resolves without network or a configured host',
    () async {
      final store = ModelAssets(
        manifest: {'row': entry(bundled: true)},
        cache: MemoryCache(),
      );
      expect((await store.resolve('row')).src, 'assets/models/athlete_row.glb');
    },
  );
  test(
    'native missing host gives an actionable error instead of localhost',
    () async {
      final store = ModelAssets(
        manifest: {'row': entry()},
        cache: MemoryCache(),
      );
      await expectLater(
        store.resolve('row'),
        throwsA(isA<ModelAssetException>()),
      );
    },
  );
  test(
    'cancelled request cannot write cache or report a completed location',
    () async {
      final cache = MemoryCache();
      final request = ModelRequest()..cancel();
      final store = ModelAssets(
        manifest: {'row': entry()},
        cache: cache,
        baseUri: Uri.parse('https://example.test/'),
      );
      await expectLater(
        store.resolve('row', request: request),
        throwsA(isA<ModelDownloadCancelled>()),
      );
      expect(cache.values, isEmpty);
    },
  );
  test(
    'cache storage failure still allows a verified transient model',
    () async {
      final store = ModelAssets(
        manifest: {'row': entry()},
        cache: UnavailableCache(),
        baseUri: Uri.parse('https://example.test/'),
        clientFactory: () =>
            MockClient((_) async => http.Response.bytes(packed, 200)),
      );
      expect((await store.resolve('row')).src, startsWith('memory:'));
    },
  );
  test('a continuously trickling stream has a total deadline', () async {
    final cache = MemoryCache();
    final store = ModelAssets(
      manifest: {'row': entry()},
      cache: cache,
      baseUri: Uri.parse('https://example.test/'),
      transferTimeout: const Duration(milliseconds: 60),
      clientFactory: () => MockClient.streaming(
        (_, _) async => http.StreamedResponse(
          Stream.periodic(const Duration(milliseconds: 10), (_) => [0]),
          200,
        ),
      ),
    );
    await expectLater(
      store.resolve('row'),
      throwsA(
        isA<ModelAssetException>().having(
          (e) => e.message,
          'message',
          contains('超时'),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(cache.values, isEmpty);
  });
  test(
    'cancel during download rejects late result and preserves cache',
    () async {
      final cache = MemoryCache();
      final token = ModelRequest();
      final store = ModelAssets(
        manifest: {'row': entry()},
        cache: cache,
        baseUri: Uri.parse('https://example.test/'),
        clientFactory: () => MockClient.streaming(
          (_, _) async => http.StreamedResponse(Stream.value(packed), 200),
        ),
      );
      await expectLater(
        store.resolve(
          'row',
          request: token,
          onProgress: (received, total, stage) {
            if (received > 0 && stage == '下载动作') token.cancel();
          },
        ),
        throwsA(isA<ModelDownloadCancelled>()),
      );
      expect(cache.values, isEmpty);
    },
  );
}
