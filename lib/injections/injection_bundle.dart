import 'dart:collection';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// All CSS/JS/HTML customizations from `assets/injections/`, discovered from
/// the asset manifest so nobody has to register new files anywhere.
/// See `assets/injections/README.md` for the conventions.
class InjectionBundle {
  InjectionBundle({
    required this.runtime,
    required this.css,
    required this.js,
    required this.html,
  });

  static const String root = 'assets/injections';

  /// Contents of `runtime.js`. Contains the `__KW_HAB_HTML__` placeholder.
  final String runtime;

  /// Area name -> file contents, sorted by area name.
  final SplayTreeMap<String, String> css;
  final SplayTreeMap<String, String> js;
  final SplayTreeMap<String, String> html;

  static Future<InjectionBundle> load(AssetBundle bundle) async {
    final manifest = await AssetManifest.loadFromAssetBundle(bundle);
    final assets = manifest.listAssets();

    Future<SplayTreeMap<String, String>> folder(String sub, String ext) async {
      final result = SplayTreeMap<String, String>();
      for (final path in assets) {
        if (!path.startsWith('$root/$sub/') || !path.endsWith(ext)) continue;
        final file = path.substring(path.lastIndexOf('/') + 1);
        if (file.startsWith('_')) continue;
        result[file.substring(0, file.length - ext.length)] =
            await bundle.loadString(path, cache: false);
      }
      return result;
    }

    return InjectionBundle(
      runtime: await bundle.loadString('$root/runtime.js', cache: false),
      css: await folder('css', '.css'),
      js: await folder('js', '.js'),
      html: await folder('html', '.html'),
    );
  }

  /// JS that adds one `<style data-kw-area="...">` per CSS file and re-adds
  /// them if Facebook replaces `<head>`.
  String cssBootstrapScript() => '''
(function () {
  var sheets = ${jsonEncode(css)};
  function apply() {
    Object.keys(sheets).forEach(function (area) {
      if (document.querySelector('style[data-kw-area="' + area + '"]')) return;
      var style = document.createElement('style');
      style.setAttribute('data-kw-area', area);
      style.textContent = sheets[area];
      (document.head || document.documentElement).appendChild(style);
    });
  }
  function start() {
    apply();
    new MutationObserver(apply).observe(document.documentElement, { childList: true });
  }
  // WebView2 (Chromium) runs document-start scripts before <html> exists;
  // WebKit already has it. Wait for it rather than throwing.
  if (document.documentElement) {
    start();
  } else {
    new MutationObserver(function (_, observer) {
      if (!document.documentElement) return;
      observer.disconnect();
      start();
    }).observe(document, { childList: true });
  }
})();
//# sourceURL=kw-hab/css-bootstrap.js
''';

  String runtimeScript() =>
      '${runtime.replaceFirst('__KW_HAB_HTML__', jsonEncode(html))}\n'
      '//# sourceURL=kw-hab/runtime.js\n';

  /// Wraps one area script so it starts once `<body>` exists, a throw can't
  /// affect other areas, and the Web Inspector can name it.
  static String wrapAreaScript(String area, String source) => '''
window.kwHab._whenBody(function () {
  try {
$source
  } catch (e) {
    console.error('[kwHab:$area]', e);
  }
});
//# sourceURL=kw-hab/js/$area.js
''';

  UnmodifiableListView<UserScript> userScripts() => UnmodifiableListView([
        UserScript(
          groupName: 'kw-hab',
          source: cssBootstrapScript(),
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
        UserScript(
          groupName: 'kw-hab',
          source: runtimeScript(),
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
        for (final entry in js.entries)
          UserScript(
            groupName: 'kw-hab',
            source: wrapAreaScript(entry.key, entry.value),
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          ),
      ]);
}
