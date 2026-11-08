import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../injections/injection_bundle.dart';
import '../settings/settings_scope.dart';
import 'downloads.dart';
import 'page_bridge.dart';
import 'url_routing.dart';
import 'windows_messenger_worker.dart';

/// Appended to WebKit's default user agent so Facebook serves the full desktop
/// Safari experience instead of an "unsupported browser" fallback.
const String kSafariUserAgentSuffix = 'Version/26.0 Safari/605.1.15';

InAppWebViewSettings _webViewSettings() => InAppWebViewSettings(
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
      initialUserScripts: UnmodifiableListView([
        for (final bridge in widget.bridges) ...bridge.initialUserScripts(),
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
        return PermissionResponse(
          resources: request.resources,
          action: trusted ? PermissionResponseAction.GRANT : PermissionResponseAction.DENY,
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
        return Dialog(
          clipBehavior: Clip.antiAlias,
          insetPadding: const EdgeInsets.all(32),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: SizedBox(
            width: (size.width * 0.8).clamp(480, 1100),
            height: (size.height * 0.85).clamp(400, 900),
            child: Column(
              children: [
                Container(
                  height: 40 * SettingsScope.of(dialogContext).accessibility.buttonScale,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.centerRight,
                  color: const Color(0xFFF0F2F5),
                  child: IconButton(
                    tooltip: 'Close',
                    iconSize: 18 * SettingsScope.of(dialogContext).accessibility.buttonScale,
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
        );
      },
    );
  }
}
