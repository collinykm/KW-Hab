// Phone/tablet support must never change the Mac app. These tests keep it
// that way: the Mac has no mobile behaviour, and everything in
// css/mobile.css and js/mobile.js needs the html[data-kw-mobile] mark that
// only the Android/iOS app sets (lib/shell/platform.dart).
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kw_hab/injections/injection_bundle.dart';
import 'package:kw_hab/shell/platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InjectionBundle bundle;
  setUpAll(() async => bundle = await InjectionBundle.load(rootBundle));

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('the Mac is not a mobile platform and keeps its own user agent', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(isMobile, isFalse);
    expect(isAndroid, isFalse);
    expect(isIOS, isFalse);
    mobileDesktopUserAgent = null;
    await loadMobileDesktopUserAgent();
    expect(mobileDesktopUserAgent, isNull);
  });

  test('Android and iOS are mobile', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(isMobile, isTrue);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(isMobile, isTrue);
  });

  test('phones ask for the desktop site', () {
    final chrome = desktopChromeUserAgent('150.0.1.2');
    expect(chrome, contains('Chrome/150.0.1.2'));
    expect(chrome, isNot(contains('Mobile')));
    expect(chrome, isNot(contains('Android')));
    expect(kDesktopSafariUserAgent, contains('Macintosh'));
    expect(kDesktopSafariUserAgent, isNot(contains('Mobile')));
  });

  test('every mobile.css rule requires html[data-kw-mobile]', () {
    final css = bundle.css['mobile'];
    expect(css, isNotNull);
    // Drop comments, then check every selector list in front of a block.
    final source = css!.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
    final selectors = RegExp(r'([^{}]+)\{')
        .allMatches(source)
        .map((m) => m.group(1)!.trim())
        .where((s) => !s.startsWith('@'))
        .toList();
    expect(selectors, isNotEmpty);
    for (final list in selectors) {
      for (final selector in _splitTopLevel(list)) {
        expect(selector.trim(), startsWith('html[data-kw-mobile]'),
            reason: 'mobile.css rule "$selector" would also apply on the Mac');
      }
    }
  });

  test('mobile.js does nothing without html[data-kw-mobile]', () {
    final js = bundle.js['mobile'];
    expect(js, isNotNull);
    final code = js!
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//') && l.trim().isNotEmpty)
        .toList();
    expect(code.first, "if (document.documentElement.hasAttribute('data-kw-mobile')) {");
    expect(code.last, '}');
  });

  test('the page script marks the page and gives it a viewport', () {
    expect(kMobilePageScript, contains("setAttribute('data-kw-mobile'"));
    expect(kMobilePageScript, contains('width=device-width'));
  });
}

/// Splits a selector list on its top-level commas (not those inside
/// `:is(…)`, `:has(…)` etc.).
List<String> _splitTopLevel(String list) {
  final parts = <String>[];
  var depth = 0;
  var start = 0;
  for (var i = 0; i < list.length; i++) {
    final c = list[i];
    if (c == '(') depth++;
    if (c == ')') depth--;
    if (c == ',' && depth == 0) {
      parts.add(list.substring(start, i));
      start = i + 1;
    }
  }
  parts.add(list.substring(start));
  return parts;
}
