import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// A Dart-side service that page scripts in `assets/injections/js/` can call
/// through `window.flutter_inappwebview.callHandler(name, …)`.
///
/// Secrets and calls to outside services stay behind a bridge, because
/// Facebook's own scripts can read anything in the page. Bridges are built in
/// `main.dart` and attached to every web view (main window and popups).
///
/// Facebook's scripts can call these handlers too. Treat every argument as
/// untrusted input and never return anything secret.
abstract class PageBridge {
  void attach(InAppWebViewController controller);
}
