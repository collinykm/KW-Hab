# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Flutter desktop wrapper around facebook.com, built for **macOS**. The app window is the Facebook website in a WKWebView, restyled and extended with injected CSS/JS/HTML, plus native menus. Only the macOS UI matters; the iOS, Android and Windows targets are unmaintained template leftovers. Several people work on different UI areas in parallel, so the layout is organized to keep each area in its own files.

## Commands

```bash
flutter run -d macos                 # run; press R (hot restart) to pick up asset/CSS/JS changes
flutter build macos --debug          # build to build/macos/Build/Products/Debug/kw_hab.app
flutter analyze                      # lint (flutter_lints)
flutter test                         # all tests
flutter test test/injection_bundle_test.dart --plain-name "<test name>"   # single test
```

CocoaPods is **not** installed on this machine. Every plugin must support Swift Package Manager, which is why `flutter_inappwebview` is pinned to the `6.2.0-beta` line (the 6.1.x stable needs CocoaPods). If a build ever adds `Podfile`s or `Pods` entries to `project.pbxproj`/xcconfigs, revert them rather than installing CocoaPods.

## Layout

```
assets/injections/   Facebook UI customizations: css/, js/, html/ (one file per area) + runtime.js
lib/injections/      InjectionBundle: discovers those assets and turns them into WKUserScripts
lib/shell/           the web view host: window, navigation/link routing, popups, downloads, native bridge
lib/app.dart         root widget; native Flutter screens (e.g. a custom login/onboarding under lib/screens/) route from here
macos/Runner/        native window + menu bar
```

## UI injections (`assets/injections/`)

The full conventions are in `assets/injections/README.md`. The key points:
- Files are **auto-discovered** from the asset manifest (`InjectionBundle.load`). A new area means new files only, never a shared registry. Files prefixed `_` are ignored (templates). There are no subfolders unless they're added to `pubspec.yaml` `assets:`.
- Injection order per page: at document start, one `<style data-kw-area="…">` per CSS file (re-added if Facebook replaces `<head>`), then `runtime.js`. At document end, each `js/*.js` file runs as its own user script wrapped in try/catch. HTML files are only used through `kwHab.html()`/`kwHab.fragment()` from JS.
- `runtime.js` defines `window.kwHab` (`onNavigate`, `onElement`, `html`, `fragment`, `log`). Facebook is a single-page app with a constantly re-rendered DOM, so area scripts should use `onNavigate`/`onElement` instead of one-off DOM queries or their own observers.
- Facebook class names are obfuscated and unstable. Select on `role`, `aria-label`, `data-pagelet`, `href`. Prefix created classes/ids with `kw-`.
- Debug builds set `isInspectable`, so you can right-click the page → Inspect Element. Scripts appear under `kw-hab/…` source URLs.

## Shell (`lib/shell/` + `macos/Runner/`)

- `FacebookWebView` is shared by the main window and `window.open()` popups (popups pass `windowId` and show in a `Dialog`). It applies the injections, user agent, permissions and download handling.
- `url_routing.dart`: hosts in `kInAppDomains` stay in-app. Other main-frame navigations and new windows open in the default browser. Facebook's `l.facebook.com/l.php?u=` link shim is unwrapped first.
- User agent: a Safari `Version/… Safari/…` suffix is appended so Facebook serves the full desktop site.
- Downloads: the plugin cancels WebKit downloads natively, so `downloads.dart` re-fetches the file with the web view's cookies into `~/Downloads`.
- Native bridge: the `kw_hab/shell` MethodChannel (`native_shell.dart` ↔ `MainFlutterWindow.swift`). Native → Dart sends `menu` commands (reload/back/forward/home/zoom). Dart → native sends `setTitle`.
- Shortcuts are native `NSMenu` key equivalents on purpose: when the WKWebView has focus, Flutter never sees key events. Don't replace the xib menu with Flutter's `PlatformMenuBar`, because that drops the Edit menu and breaks copy/paste in the web view.
- Entitlements (`DebugProfile`/`Release`, keep in sync) need `network.client`, camera, audio-input, user-selected files and downloads access. Camera/mic usage strings are in `Info.plist`.
