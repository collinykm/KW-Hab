import 'package:flutter/services.dart';

/// Bridge to `macos/Runner/MainFlutterWindow.swift` (and, for
/// [requestPermissions], `android/.../MainActivity.kt`).
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

  /// Android only (`MainActivity.kt`): asks the user for the app's own camera
  /// and/or microphone permission, which a web view needs before it can grant
  /// them to a page. [names] are "camera" and "microphone"; returns the ones
  /// the user allowed.
  static Future<Set<String>> requestPermissions(Set<String> names) async {
    try {
      final granted = await _channel.invokeListMethod<String>('requestPermissions', names.toList());
      return {...?granted};
    } on MissingPluginException {
      return names; // No native side: the platform has nothing to ask.
    }
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
