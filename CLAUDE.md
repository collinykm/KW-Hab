# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

Built with [KW Habilitation](https://kwhab.ca/) to make an accessible social platform that **seniors and adults with intellectual or developmental disabilities** can use independently and safely.

- **Independence:** help users engage with the outside world on their own terms.
- **Safety:** guardrails that protect users.
- **Accessibility:** larger fonts, more input/output modes (text-to-speech via ElevenLabs, speech-to-text for input), image adjustments for colour-blind users, etc.
- **Simplicity:** strip away excess Facebook features to simplify the experience.
- **Balance:** simplification and guardrails also take choices away from users. Weigh every removal or restriction against the erosion of independence; don't hide or block something just because it's possible.

Judge UI changes by these audiences, not by what a typical Facebook user expects.

## What this is

A Flutter wrapper around facebook.com, built for **macOS** first, and also for **Android and iOS** phones and tablets. The app window is the Facebook website in a web view (WKWebView; Android's system WebView), restyled and extended with injected CSS/JS/HTML, plus native menus on the Mac. The Windows target is an unmaintained template leftover.

Phones and tablets get the same desktop Facebook site, not m.facebook.com, so every injection works there too (see "Phones and tablets" below). Mobile support must never change the Mac app: gate Dart on `isMobile`/`isAndroid`/`isIOS` (`lib/shell/platform.dart`), and page CSS/JS on `html[data-kw-mobile]`. `test/mobile_test.dart` enforces the page side. Several people work on different UI areas in parallel, so the layout is organized to keep each area in its own files.

Injected JS runs inside Facebook's page, so Facebook's own scripts can read anything in it. Keep secrets (e.g. the ElevenLabs API key) and calls to outside services on the Dart side, and reach them from the page through a bridge, not from `assets/injections/`.

## Commands

```bash
flutter run -d macos                 # run; press R (hot restart) to pick up asset/CSS/JS changes
flutter run -d <android-or-ios-device> # phones/tablets (`flutter devices` lists them)
flutter build macos --debug          # build to build/macos/Build/Products/Debug/kw_hab.app
flutter analyze                      # lint (flutter_lints)
flutter test                         # all tests
flutter test test/injection_bundle_test.dart --plain-name "<test name>"   # single test
```

CocoaPods is **not** installed on this machine. Every plugin must support Swift Package Manager (iOS too), which is why `flutter_inappwebview` is pinned to the `6.2.0-beta` line (the 6.1.x stable needs CocoaPods). If a build ever adds `Podfile`s or `Pods` entries to `project.pbxproj`/xcconfigs, revert them rather than installing CocoaPods.

## Layout

```
assets/injections/   Facebook UI customizations: css/, js/, html/ (one file per area) + runtime.js
lib/injections/      InjectionBundle: discovers those assets and turns them into WKUserScripts
lib/shell/           the web view host: window, navigation/link routing, popups, downloads, native bridge
lib/settings/        AppSettings: user settings (accessibility, support contacts, onboarding done), saved to settings.json
lib/screens/         native Flutter screens; onboarding/ = first-run setup + Settings… (⌘,)
lib/monitoring/      message monitoring: Messenger snapshots -> Gemini -> staff alert (Gemini key in git-ignored `.env`, copy `.env.example`)
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

## Settings (`lib/settings/`)

`AppSettings` (a `ChangeNotifier`, built and loaded in `main.dart`) is the single source of truth for user settings, saved to `settings.json` in Application Support on every change. Reach it from widgets with `SettingsScope.of(context)`, from Dart services by taking it as a constructor argument, and from page JS/CSS through `kwHab.settings` / `--kw-*` (pushed by `PageSettingsBridge`; see `assets/injections/README.md`). Only accessibility settings go to the page; support contacts stay in Dart. Flutter screens get text size/bold/button size from `accessibility_theme.dart`.

Onboarding (`lib/screens/onboarding/`) is shown by `FacebookShell` after a page load when Facebook's `c_user` login cookie is present and `onboardingComplete` is false, and again from the app menu's Settings… (⌘,) or the "Settings" item `js/top-bar.js` adds to Facebook's profile menu (via the `kwOpenSettings` bridge, `OpenSettingsBridge`).

## Shell (`lib/shell/` + `macos/Runner/`)

- `FacebookWebView` is shared by the main window and `window.open()` popups (popups pass `windowId` and show in a `Dialog`). It applies the injections, user agent, permissions and download handling.
- `url_routing.dart`: hosts in `kInAppDomains` stay in-app. Other main-frame navigations and new windows open in the default browser. Facebook's `l.facebook.com/l.php?u=` link shim is unwrapped first.
- User agent: a Safari `Version/… Safari/…` suffix is appended so Facebook serves the full desktop site.
- Downloads: the plugin cancels WebKit downloads natively, so `downloads.dart` re-fetches the file with the web view's cookies into `~/Downloads`.
- Page bridges (`page_bridge.dart`): Dart services that page JS calls via `window.flutter_inappwebview.callHandler`. Built in `main.dart`, attached to every web view. Facebook's scripts can call them too, so treat arguments as untrusted. The message monitor (`kwMessageMonitor`) is one.
- Native bridge: the `kw_hab/shell` MethodChannel (`native_shell.dart` ↔ `MainFlutterWindow.swift`). Native → Dart sends `menu` commands (reload/back/forward/home/zoom/settings). Dart → native sends `setTitle`.
- Shortcuts are native `NSMenu` key equivalents on purpose: when the WKWebView has focus, Flutter never sees key events. Don't replace the xib menu with Flutter's `PlatformMenuBar`, because that drops the Edit menu and breaks copy/paste in the web view.
- Entitlements (`DebugProfile`/`Release`, keep in sync) need `network.client`, camera, audio-input, user-selected files and downloads access. Camera/mic usage strings are in `Info.plist`.

## Phones and tablets (Android, iOS)

- `lib/shell/platform.dart`: `isMobile`, and the desktop user agent phones send (desktop Chrome on Android with the WebView's own version, desktop Safari on iOS) so Facebook serves the desktop site. `kMobilePageScript` (added only on mobile) marks the page `html[data-kw-mobile]` and gives it a `width=device-width` viewport; Android also uses `useWideViewPort: false`.
- `FacebookWebView` builds separate `_desktopSettings()` (the Mac's, unchanged) and `_mobileSettings()`. Mobile adds pull-to-refresh (no menu bar), full-screen popups on narrow screens, and downloads handed to the device's browser (`downloads.dart`).
- Android: the back gesture goes back in the web view (`PopScope` in `FacebookShell`). Camera/mic need the app's own runtime permission first: `NativeShell.requestPermissions` → `MainActivity.kt` on the `kw_hab/shell` channel. Permissions in `AndroidManifest.xml`. iOS: camera/mic/photos usage strings in `ios/Runner/Info.plist`.
- `css/mobile.css` + `js/mobile.js` rearrange the desktop site for screens under 600px wide: Facebook's middle tabs become a bottom tab bar (hidden inside a conversation and while typing), Back moves into the top bar, docked Messenger chats fill the screen, and post action buttons share the width. Tablets keep the desktop layout.
- Flutter screens use `SafeArea` for the status bar and home indicator (a no-op on the Mac), and say "tap" instead of "click" on mobile.
- Debug builds can be inspected: Android from `chrome://inspect`, iOS from Safari's Develop menu.
