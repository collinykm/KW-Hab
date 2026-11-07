import 'package:flutter/services.dart';

/// Bridge to `macos/Runner/MainFlutterWindow.swift`.
///
/// Native -> Dart: `menu` with a command string (reload, back, forward, home,
/// zoomIn, zoomOut, zoomReset).
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

  static Future<void> setTitle(String title) => _channel.invokeMethod('setTitle', title);
}
