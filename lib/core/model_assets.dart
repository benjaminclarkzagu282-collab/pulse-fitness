import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'model_cache_stub.dart'
    if (dart.library.io) 'model_cache_native.dart'
    if (dart.library.js_interop) 'model_cache_web.dart'
    as platform;

class ModelAssetException implements Exception {
  final String message;
  const ModelAssetException(this.message);
  @override
  String toString() => message;
}

class ModelDownloadCancelled implements Exception {}

class ModelRequest {
  bool cancelled = false;
  http.Client? client;
  void cancel() {
    cancelled = true;
    client?.close();
  }

  void check() {
    if (cancelled) throw ModelDownloadCancelled();
  }
}

class ModelLocation {
  final String src;
  final void Function()? onRelease;
  ModelLocation(this.src, [this.onRelease]);
  bool _released = false;
  void release() {
    if (_released) return;
    _released = true;
    onRelease?.call();
  }
}

abstract class ModelCache {
  Future<Uint8List?> read(String key);
  Future<void> write(String key, Uint8List bytes);
  Future<void> remove(String key);
  Future<void> clear();
  Future<ModelLocation> location(String key, Uint8List bytes);
}

class ModelAsset {
  final String id, sha256Hex, compressedSha256;
  final int bytes, compressedBytes;
  final bool bundled;
  const ModelAsset({
    required this.id,
    required this.bytes,
    required this.compressedBytes,
    required this.sha256Hex,
    required this.compressedSha256,
    required this.bundled,
  });
  String get cacheKey => '$id-$sha256Hex.glb';
  String get remotePath => 'remote/models/athlete_$id.glb.gz';
  factory ModelAsset.fromJson(String id, Map<String, dynamic> json) =>
      ModelAsset(
        id: id,
        bytes: json['bytes'] as int,
        compressedBytes: json['compressedBytes'] as int,
        sha256Hex: json['sha256'] as String,
        compressedSha256: json['compressedSha256'] as String,
        bundled: json['bundled'] as bool,
      );
}

Uint8List _decodeVerified(List<Object> args) {
  final packed = args[0] as Uint8List;
  final expectedPacked = args[1] as String;
  final expectedRaw = args[2] as String;
  final expectedSize = args[3] as int;
  if (sha256.convert(packed).toString() != expectedPacked) {
    throw const ModelAssetException('下载文件校验失败，请重新下载。');
  }
  final raw = Uint8List.fromList(
    GZipDecoder().decodeBytes(packed, verify: true),
  );
  if (raw.length != expectedSize ||
      sha256.convert(raw).toString() != expectedRaw) {
    throw const ModelAssetException('模型完整性校验失败，请重新下载。');
  }
  return raw;
}

class ModelAssets {
  final Map<String, ModelAsset> manifest;
  final ModelCache cache;
  final Uri? baseUri;
  final Duration transferTimeout;
  final http.Client Function() clientFactory;
  ModelAssets({
    required this.manifest,
    required this.cache,
    this.baseUri,
    this.transferTimeout = const Duration(minutes: 3),
    http.Client Function()? clientFactory,
  }) : clientFactory = clientFactory ?? http.Client.new;

  static Future<ModelAssets>? _shared;
  static Future<ModelAssets> get shared =>
      _shared ??= _load().catchError((Object error) {
        _shared = null;
        throw error;
      });
  static Future<ModelAssets> _load() async {
    final json = jsonDecode(
      await rootBundle.loadString('assets/muscles/model_manifest.json'),
    ) as Map<String, dynamic>;
    const configured = String.fromEnvironment('PULSE_ASSET_BASE_URL');
    final base = configured.isNotEmpty
        ? Uri.parse(configured.endsWith('/') ? configured : '$configured/')
        : kIsWeb
        ? Uri.base.resolve('./')
        : null;
    return ModelAssets(
      manifest: (json['models'] as Map<String, dynamic>).map(
        (id, value) => MapEntry(
          id,
          ModelAsset.fromJson(id, Map<String, dynamic>.from(value)),
        ),
      ),
      cache: platform.createModelCache(),
      baseUri: base,
    );
  }

  Future<ModelLocation> resolve(
    String id, {
    ModelRequest? request,
    void Function(int received, int total, String stage)? onProgress,
  }) async {
    final token = request ?? ModelRequest();
    token.check();
    final entry = manifest[id];
    if (entry == null) throw const ModelAssetException('这个动作的资源尚未准备好。');
    if (entry.bundled) return ModelLocation('assets/models/athlete_$id.glb');
    onProgress?.call(0, 0, '检查离线缓存');
    Uint8List? saved;
    try {
      saved = await cache.read(entry.cacheKey);
    } catch (_) {
      // Private browsing and storage quotas may disable persistent caching.
    }
    token.check();
    if (saved != null) {
      if (saved.length == entry.bytes &&
          sha256.convert(saved).toString() == entry.sha256Hex) {
        final result = await cache.location(entry.cacheKey, saved);
        if (token.cancelled) {
          result.release();
          token.check();
        }
        return result;
      }
      try {
        await cache.remove(entry.cacheKey);
      } catch (_) {
        /* A failed cache must not prevent a fresh download. */
      }
    }
    if (baseUri == null || !['http', 'https'].contains(baseUri!.scheme)) {
      throw const ModelAssetException(
        '此动作尚未下载。当前版本未连接动作资源服务，可先查看轻量视频或使用内置深蹲、俯卧撑。',
      );
    }
    final client = clientFactory();
    token.client = client;
    var expired = false;
    void checkTransfer() {
      token.check();
      if (expired) throw const ModelAssetException('动作下载超时，可先看轻量视频后重试。');
    }

    try {
      return await (() async {
        onProgress?.call(0, entry.compressedBytes, '下载动作');
        final response = await client
            .send(http.Request('GET', baseUri!.resolve(entry.remotePath)))
            .timeout(const Duration(seconds: 25));
        if (response.statusCode != 200) {
          throw const ModelAssetException('动作下载失败，请检查网络后重试。');
        }
        final buffer = BytesBuilder(copy: false);
        var received = 0;
        await for (final chunk in response.stream.timeout(
          const Duration(seconds: 25),
        )) {
          checkTransfer();
          received += chunk.length;
          if (received > entry.compressedBytes) {
            throw const ModelAssetException('下载文件大小不符，请重试。');
          }
          buffer.add(chunk);
          onProgress?.call(received, entry.compressedBytes, '下载动作');
        }
        checkTransfer();
        if (received != entry.compressedBytes) {
          throw const ModelAssetException('下载未完成，请重试。');
        }
        onProgress?.call(received, entry.compressedBytes, '校验与解压');
        final raw = await compute(_decodeVerified, <Object>[
          buffer.takeBytes(),
          entry.compressedSha256,
          entry.sha256Hex,
          entry.bytes,
        ]);
        checkTransfer();
        try {
          await cache.write(entry.cacheKey, raw);
        } catch (_) {
          /* The platform can still offer a transient source. */
        }
        checkTransfer();
        final result = await cache.location(entry.cacheKey, raw);
        if (token.cancelled || expired) {
          result.release();
          checkTransfer();
        }
        return result;
      })().timeout(
        transferTimeout,
        onTimeout: () {
          expired = true;
          client.close();
          throw const ModelAssetException('动作下载超时，可先看轻量视频后重试。');
        },
      );
    } on ModelDownloadCancelled {
      rethrow;
    } on ModelAssetException {
      rethrow;
    } catch (_) {
      token.check();
      throw const ModelAssetException('暂时无法载入动作，请检查网络与本机存储后重试。');
    } finally {
      client.close();
      token.client = null;
    }
  }

  Future<void> clearCache() => cache.clear();
}
