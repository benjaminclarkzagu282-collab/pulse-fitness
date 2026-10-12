import 'dart:js_interop';
import 'dart:ui';

import 'package:web/web.dart' as web;

Future<bool> exportBackupFile(String json, String filename, Rect origin) async {
  final blob = web.Blob(
    [json.toJS].toJS,
    web.BlobPropertyBag(type: 'application/json;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  // Keep the object URL alive long enough for the browser to start the download.
  Future<void>.delayed(
    const Duration(seconds: 30),
    () => web.URL.revokeObjectURL(url),
  );
  return true;
}
