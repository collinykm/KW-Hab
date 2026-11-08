import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../shell/page_bridge.dart';
import 'app_settings.dart';

/// Sends the accessibility settings into every web view, and pushes changes
/// live (no reload).
///
/// In the page, `runtime.js` turns them into:
/// - `kwHab.settings` (current values) and `kwHab.onSettings(cb)`
/// - `--kw-text-scale` / `--kw-button-scale` CSS variables on `<html>`
/// - `data-kw-bold-text`, `data-kw-read-aloud`, `data-kw-talk-to-type`
///   attributes on `<html>` (present when the feature is on)
///
/// Only [AccessibilitySettings.toPageJson] crosses over. Support contacts never
/// do, since Facebook's scripts can read the page.
class PageSettingsBridge extends PageBridge {
  PageSettingsBridge(this.settings) : _lastSent = settings.accessibility.toPageJson() {
    settings.addListener(_onSettingsChanged);
  }

  static const String groupName = 'kw-hab-settings';

  final AppSettings settings;
  final Set<InAppWebViewController> _controllers = {};
  Map<String, Object?> _lastSent;

  /// Sets `window.__kwHabSettings` and, if the runtime is already loaded,
  /// applies it. Order-independent with `runtime.js`.
  @visibleForTesting
  static String scriptFor(Map<String, Object?> pageSettings) => '''
(function () {
  var s = ${jsonEncode(pageSettings)};
  window.__kwHabSettings = s;
  if (window.kwHab && window.kwHab._applySettings) window.kwHab._applySettings(s);
})();
//# sourceURL=kw-hab/settings.js
''';

  UserScript _userScript() => UserScript(
        groupName: groupName,
        source: scriptFor(settings.accessibility.toPageJson()),
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      );

  @override
  List<UserScript> initialUserScripts() => [_userScript()];

  @override
  void attach(InAppWebViewController controller) => _controllers.add(controller);

  @override
  void detach(InAppWebViewController controller) => _controllers.remove(controller);

  void _onSettingsChanged() {
    final page = settings.accessibility.toPageJson();
    if (mapEquals(page, _lastSent)) return;
    _lastSent = page;
    for (final c in _controllers.toList()) {
      _push(c);
    }
  }

  Future<void> _push(InAppWebViewController c) async {
    try {
      // Replace the document-start script so the next full page load starts
      // with the new values, then update the page that's showing now.
      await c.removeUserScriptsByGroupName(groupName: groupName);
      final script = _userScript();
      await c.addUserScript(userScript: script);
      await c.evaluateJavascript(source: script.source);
    } catch (e) {
      debugPrint('[kw-hab:settings] could not update a web view: $e');
    }
  }

  void dispose() => settings.removeListener(_onSettingsChanged);
}
