import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Where [AppSettings] are saved. Swappable so tests don't touch the disk.
abstract class SettingsStorage {
  /// The saved settings, or null if nothing has been saved yet.
  Future<Map<String, Object?>?> read();
  Future<void> write(Map<String, Object?> json);
}

/// `settings.json` in the app's Application Support folder (inside the app
/// sandbox container on macOS).
class FileSettingsStorage implements SettingsStorage {
  FileSettingsStorage([this._file]);

  File? _file;

  Future<File> _resolve() async =>
      _file ??= File('${(await getApplicationSupportDirectory()).path}/settings.json');

  @override
  Future<Map<String, Object?>?> read() async {
    final file = await _resolve();
    try {
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException catch (e) {
      // A corrupt file shouldn't lock the user out; start fresh (onboarding
      // shows again) and keep the bad file for inspection.
      debugPrint('[kw-hab:settings] unreadable ${file.path}: ${e.message}');
      await file.rename('${file.path}.corrupt').catchError((_) => file);
      return null;
    }
  }

  @override
  Future<void> write(Map<String, Object?> json) async {
    final file = await _resolve();
    await file.parent.create(recursive: true);
    // Write then rename, so a crash mid-write can't leave a half-written file.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(json), flush: true);
    await tmp.rename(file.path);
  }
}

/// Keeps settings in memory only (tests, previews).
class MemorySettingsStorage implements SettingsStorage {
  MemorySettingsStorage([this.saved]);

  Map<String, Object?>? saved;
  int writes = 0;

  @override
  Future<Map<String, Object?>?> read() async => saved;

  @override
  Future<void> write(Map<String, Object?> json) async {
    writes++;
    saved = jsonDecode(jsonEncode(json)) as Map<String, Object?>;
  }
}
