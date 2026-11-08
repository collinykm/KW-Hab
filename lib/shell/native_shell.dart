import 'package:flutter/services.dart';

/// Bridge to `macos/Runner/MainFlutterWindow.swift`.
///
/// Native -> Dart: `menu` with a command string (reload, back, forward, home,
/// zoomIn, zoomOut, zoomReset, settings).
/// Dart -> native: `setTitle` with the window title.
class NativeShell {
  NativeShell._();

  static const MethodChannel _channel = MethodChannel('kw_hab/shell');

  static void onMenuCommand(Future<void> Function(String command)? handler) {
    _channel.setMethodCallHandler(handler == null
        ? null
        : (call) async {
            if (call.method == 'menu') await handler(call.arguments as String);
          });
  }

  /// Only macOS implements this; elsewhere (e.g. the Windows runner) there is
  /// no native handler, so skip it quietly instead of logging an error on
  /// every page title change.
  static Future<void> setTitle(String title) async {
    try {
      await _channel.invokeMethod('setTitle', title);
    } on MissingPluginException {
      // No native side on this platform.
    }
  }
}
