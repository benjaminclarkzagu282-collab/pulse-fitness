import 'dart:ui';

import 'backup_export_native.dart'
    if (dart.library.js_interop) 'backup_export_web.dart'
    as platform;

Future<bool> exportBackupFile(String json, String filename, Rect origin) =>
    platform.exportBackupFile(json, filename, origin);
