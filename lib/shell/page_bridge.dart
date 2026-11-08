import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// A Dart-side service connected to every web view (main window and popups):
/// page scripts in `assets/injections/js/` can call it through
/// `window.flutter_inappwebview.callHandler(name, …)`, and it can push data
/// into the page.
///
/// Secrets and calls to outside services stay behind a bridge, because
/// Facebook's own scripts can read anything in the page. Bridges are built in
/// `main.dart`.
///
/// Facebook's scripts can call these handlers too. Treat every argument as
/// untrusted input and never return anything secret.
abstract class PageBridge {
  /// Scripts to install when a web view is created, so they are in place
  /// before its first page loads.
  List<UserScript> initialUserScripts() => const [];

  /// Called once per web view, when it is created.
  void attach(InAppWebViewController controller);

  /// Called when a web view is disposed (e.g. a popup closes). Drop any
  /// reference to [controller].
  void detach(InAppWebViewController controller) {}
}
