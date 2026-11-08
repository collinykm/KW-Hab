import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// The app is built for macOS first. Everything that behaves differently on
/// phones and tablets checks [isMobile] (or [isAndroid]/[isIOS]), so the Mac
/// app keeps exactly its own behaviour.
bool get isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
bool get isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// Android or iOS: a touch screen, often narrow, with no menu bar.
bool get isMobile => isAndroid || isIOS;

/// The user agent phones and tablets send instead of their own, or null on
/// the Mac (which keeps WebKit's own user agent plus a Safari suffix).
///
/// Facebook serves a phone's web view its mobile site (m.facebook.com),
/// whose pages are built completely differently, so none of the
/// customizations in `assets/injections/` would apply. Sending a desktop
/// browser's user agent gets the full desktop site, which lays itself out
/// for a narrow screen, and every customization keeps working.
String? mobileDesktopUserAgent;

/// Works out [mobileDesktopUserAgent]. Call once before the first web view is
/// created.
///
/// Android: desktop Chrome, with the system web view's own (current) Chrome
/// version. iOS: desktop Safari, which is what WKWebView really is.
Future<void> loadMobileDesktopUserAgent() async {
  if (isIOS) {
    mobileDesktopUserAgent = kDesktopSafariUserAgent;
    return;
  }
  if (!isAndroid) return;
  var chromeVersion = '142.0.0.0';
  try {
    final ua = await InAppWebViewController.getDefaultUserAgent();
    final match = RegExp(r'Chrome/([\d.]+)').firstMatch(ua);
    if (match != null) chromeVersion = match.group(1)!;
  } catch (e) {
    debugPrint('[kw-hab:shell] could not read the web view user agent: $e');
  }
  mobileDesktopUserAgent = desktopChromeUserAgent(chromeVersion);
}

/// A desktop (Linux) Chrome user agent for [chromeVersion].
String desktopChromeUserAgent(String chromeVersion) =>
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/$chromeVersion Safari/537.36';

/// Desktop Safari on a Mac (iPadOS sends the same by default).
const String kDesktopSafariUserAgent =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 '
    '(KHTML, like Gecko) Version/26.0 Safari/605.1.15';

/// Runs at document start on phones and tablets only (never on the Mac):
///
/// - Marks the page `<html data-kw-mobile>`. `css/mobile.css` and
///   `js/mobile.js` only act when it is there, so nothing they do can reach
///   the Mac app, whatever its window size.
/// - Gives the desktop site a viewport tag, so it is laid out at the
///   screen's own width instead of a zoomed-out 980px page with tiny text
///   (iOS; Android does the same through `useWideViewPort: false`).
///
/// Facebook rewrites `<html>`'s attributes and `<head>` as it navigates, so
/// both are put back whenever they go missing.
const String kMobilePageScript = r'''
(function () {
  var root = document.documentElement;
  function ensure() {
    if (!root.hasAttribute('data-kw-mobile')) root.setAttribute('data-kw-mobile', '');
    var head = document.head;
    if (head && !head.querySelector('meta[name="viewport"][data-kw-mobile]')) {
      var meta = document.createElement('meta');
      meta.name = 'viewport';
      meta.content = 'width=device-width, initial-scale=1';
      meta.setAttribute('data-kw-mobile', '');
      head.prepend(meta);
    }
  }
  ensure();
  new MutationObserver(ensure).observe(root, { attributes: true, attributeFilter: ['data-kw-mobile'], childList: true });
  document.addEventListener('DOMContentLoaded', ensure);
})();
''';
