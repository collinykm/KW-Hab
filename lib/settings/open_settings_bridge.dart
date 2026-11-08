import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../shell/page_bridge.dart';
import '../shell/url_routing.dart';

/// Lets page JS open the native settings screen (the onboarding screen), e.g.
/// the "Settings" item `js/top-bar.js` adds to the profile menu:
///
/// ```js
/// window.flutter_inappwebview.callHandler('kwOpenSettings');
/// ```
///
/// [FacebookShell] sets [onOpen] while it is on screen. Facebook's scripts
/// could call this too; the worst they can do is open the settings screen.
class OpenSettingsBridge extends PageBridge {
  /// Must match `SETTINGS_HANDLER` in top-bar.js.
  static const String handlerName = 'kwOpenSettings';

  VoidCallback? onOpen;

  @override
  void attach(InAppWebViewController controller) {
    controller.addJavaScriptHandler(
      handlerName: handlerName,
      callback: (JavaScriptHandlerFunctionData data) {
        if (!data.isMainFrame || !isInAppHost(data.origin.host)) {
          debugPrint('[kw-hab:settings] ignored open request from ${data.origin}');
          return false;
        }
        final open = onOpen;
        if (open == null) return false;
        open();
        return true;
      },
    );
  }
}
