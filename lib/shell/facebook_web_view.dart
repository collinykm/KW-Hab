import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../injections/injection_bundle.dart';
import '../settings/settings_scope.dart';
import 'downloads.dart';
import 'native_shell.dart';
import 'page_bridge.dart';
import 'platform.dart';
import 'url_routing.dart';
import 'windows_messenger_worker.dart';

/// Appended to WebKit's default user agent so Facebook serves the full desktop
/// Safari experience instead of an "unsupported browser" fallback.
const String kSafariUserAgentSuffix = 'Version/26.0 Safari/605.1.15';

/// The Mac's settings, unchanged by the phone/tablet support.
InAppWebViewSettings _desktopSettings() => InAppWebViewSettings(
      applicationNameForUserAgent: kSafariUserAgentSuffix,
      isInspectable: kDebugMode,
      allowsBackForwardNavigationGestures: true,
      allowsLinkPreview: true,
      javaScriptCanOpenWindowsAutomatically: true,
      supportMultipleWindows: true,
      mediaPlaybackRequiresUserGesture: false,
      useShouldOverrideUrlLoading: true,
      useOnDownloadStart: true,
      isFraudulentWebsiteWarningEnabled: true,
    );

/// Phones and tablets (Android, iOS); see lib/shell/platform.dart.
InAppWebViewSettings _mobileSettings() => InAppWebViewSettings(
      // A desktop browser's user agent, so Facebook serves the same site the
      // injections are written for, not m.facebook.com.
      userAgent: mobileDesktopUserAgent,
      isInspectable: kDebugMode,
      // Android: lay the page out at the screen's own width (the desktop site
      // has no viewport tag, so the default would be a zoomed-out 980px page
      // with tiny text; iOS gets a viewport tag from kMobilePageScript).
      // Pinch zoom stays available, without Android's +/- buttons.
      useWideViewPort: false,
      loadWithOverviewMode: false,
      supportZoom: true,
      builtInZoomControls: true,
      displayZoomControls: false,
      thirdPartyCookiesEnabled: true,
      safeBrowsingEnabled: true,
      // iOS: play videos in the page, not full screen, as on the Mac.
      allowsInlineMediaPlayback: true,
      allowsBackForwardNavigationGestures: true,
      allowsLinkPreview: false,
      javaScriptCanOpenWindowsAutomatically: true,
      supportMultipleWindows: true,
      mediaPlaybackRequiresUserGesture: false,
      useShouldOverrideUrlLoading: true,
      useOnDownloadStart: true,
      isFraudulentWebsiteWarningEnabled: true,
    );

InAppWebViewSettings _webViewSettings() => isMobile ? _mobileSettings() : _desktopSettings();

/// The web view used for both the main window and `window.open()` popups.
/// Every instance gets the custom CSS/JS/HTML from [injections].
class FacebookWebView extends StatefulWidget {
  const FacebookWebView({
    super.key,
    required this.injections,
    this.bridges = const [],
    this.initialUrl,
    this.windowId,
    this.onCreated,
    this.onProgress,
    this.onTitle,
    this.onLoadStart,
    this.onLoadStop,
    this.onMainFrameError,
    this.onClose,
  });

  final InjectionBundle injections;

  /// Dart services page scripts can call; attached to every instance.
  final List<PageBridge> bridges;
  final String? initialUrl;

  /// Set when this web view backs a `window.open()` popup.
  final int? windowId;

  final ValueChanged<InAppWebViewController>? onCreated;
  final ValueChanged<double>? onProgress;
  final ValueChanged<String?>? onTitle;
  final VoidCallback? onLoadStart;

  /// A main-frame page finished loading (not called for in-app SPA navigations).
  final ValueChanged<WebUri?>? onLoadStop;
  final ValueChanged<String>? onMainFrameError;
  final VoidCallback? onClose;

  @override
  State<FacebookWebView> createState() => _FacebookWebViewState();
}

class _FacebookWebViewState extends State<FacebookWebView> {
  InAppWebViewController? _controller;

  /// Phones/tablets: pull down at the top of the page to reload it (macOS has
  /// View > Reload Page, ⌘R).
  PullToRefreshController? _pullToRefresh;

  @override
  void initState() {
    super.initState();
    if (isMobile) {
      _pullToRefresh = PullToRefreshController(
        settings: PullToRefreshSettings(color: const Color(0xFF0866FF)),
        onRefresh: () => _controller?.reload(),
      );
    }
  }

  @override
  void dispose() {
    final c = _controller;
    if (c != null) {
      for (final bridge in widget.bridges) {
        bridge.detach(c);
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      windowId: widget.windowId,
      initialUrlRequest: widget.initialUrl == null
          ? null
          : URLRequest(url: WebUri(widget.initialUrl!)),
      initialSettings: _webViewSettings(),
      pullToRefreshController: _pullToRefresh,
      initialUserScripts: UnmodifiableListView([
        for (final bridge in widget.bridges) ...bridge.initialUserScripts(),
        if (isMobile)
          UserScript(
            groupName: 'kw-mobile',
            source: kMobilePageScript,
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          ),
        ...widget.injections.userScripts(),
      ]),
      onWebViewCreated: (controller) {
        _controller = controller;
        for (final bridge in widget.bridges) {
          bridge.attach(controller);
        }
        WindowsMessengerWorker.watch(controller);
        widget.onCreated?.call(controller);
      },
      onLoadStart: (_, _) => widget.onLoadStart?.call(),
      onLoadStop: (controller, url) {
        _pullToRefresh?.endRefreshing();
        WindowsMessengerWorker.resume(controller);
        widget.onLoadStop?.call(url);
      },
      onProgressChanged: (_, p) => widget.onProgress?.call(p / 100),
      onTitleChanged: (_, t) => widget.onTitle?.call(t),
      onCloseWindow: (_) => widget.onClose?.call(),
      shouldOverrideUrlLoading: (controller, action) async {
        if (!action.isForMainFrame) return NavigationActionPolicy.ALLOW;
        final external = externalTarget(action.request.url);
        if (external == null) return NavigationActionPolicy.ALLOW;
        await openExternally(external);
        return NavigationActionPolicy.CANCEL;
      },
      onCreateWindow: (controller, action) async {
        final external = externalTarget(action.request.url);
        if (external != null) {
          await openExternally(external);
          return false;
        }
        if (!context.mounted) return false;
        _showPopup(context, action.windowId);
        return true;
      },
      onPermissionRequest: (controller, request) async {
        final trusted = isInAppHost(request.origin.host);
        if (!trusted) {
          return PermissionResponse(
            resources: request.resources,
            action: PermissionResponseAction.DENY,
          );
        }
        var resources = request.resources;
        if (isAndroid) {
          // The app needs Android's own permission first; ask the user, and
          // only pass on what they allowed.
          final names = {
            PermissionResourceType.CAMERA: 'camera',
            PermissionResourceType.MICROPHONE: 'microphone',
          };
          final wanted = {for (final r in resources) ?names[r]};
          final granted = await NativeShell.requestPermissions(wanted);
          resources = [
            for (final r in resources)
              if (names[r] == null || granted.contains(names[r])) r
          ];
        }
        return PermissionResponse(
          resources: resources,
          action: resources.isEmpty ? PermissionResponseAction.DENY : PermissionResponseAction.GRANT,
        );
      },
      onDownloadStarting: (controller, request) {
        // WebKit's own download is cancelled natively; fetch it ourselves.
        if (context.mounted) downloadFile(context, request);
        return DownloadStartResponse(handled: true);
      },
      // Debug builds: show our page scripts' logs and errors in the
      // `flutter run` output, not just the Web Inspector.
      onConsoleMessage: kDebugMode
          ? (controller, message) {
              if (message.message.contains('kwHab')) debugPrint('page: ${message.message}');
            }
          : null,
      onReceivedError: (controller, request, error) {
        if (request.isForMainFrame != true) return;
        _pullToRefresh?.endRefreshing();
        // Cancelled navigations (e.g. links we sent to the browser) aren't errors.
        if (error.type == WebResourceErrorType.CANCELLED) return;
        if (error.description.contains('Frame load interrupted')) return;
        widget.onMainFrameError?.call(error.description);
      },
    );
  }

  /// Facebook occasionally opens real windows (calls, some share/login flows).
  /// They appear as a large sheet over the main window.
  void _showPopup(BuildContext context, int windowId) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (dialogContext) {
        final size = MediaQuery.sizeOf(dialogContext);
        // Phones: the whole screen, like any other app page.
        final fullScreen = isMobile && size.width < 600;
        return Dialog(
          clipBehavior: Clip.antiAlias,
          insetPadding: fullScreen ? EdgeInsets.zero : const EdgeInsets.all(32),
          shape: fullScreen
              ? const RoundedRectangleBorder()
              : RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: SizedBox(
            width: fullScreen ? size.width : (size.width * 0.8).clamp(480, 1100),
            height: fullScreen ? size.height : (size.height * 0.85).clamp(400, 900),
            child: SafeArea(
              child: Column(
                children: [
                  Container(
                    height: (fullScreen ? 56 : 40) *
                        SettingsScope.of(dialogContext).accessibility.buttonScale,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: fullScreen ? Alignment.centerLeft : Alignment.centerRight,
                    color: const Color(0xFFF0F2F5),
                    // Phones: a labelled button, easier to find and to hit
                    // than a small X in the corner. The back gesture also closes it.
                    child: fullScreen
                        ? TextButton.icon(
                            icon: const Icon(Icons.close),
                            label: const Text('Close'),
                            onPressed: () => Navigator.of(dialogContext).pop(),
                          )
                        : IconButton(
                            tooltip: 'Close',
                            iconSize:
                                18 * SettingsScope.of(dialogContext).accessibility.buttonScale,
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(dialogContext).pop(),
                          ),
                  ),
                  Expanded(
                    child: FacebookWebView(
                      injections: widget.injections,
                      bridges: widget.bridges,
                      windowId: windowId,
                      onClose: () {
                        if (Navigator.of(dialogContext).canPop()) {
                          Navigator.of(dialogContext).pop();
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
