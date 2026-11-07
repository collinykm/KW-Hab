import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

const String kHomeUrl = 'https://www.facebook.com/';

/// Appended to WebKit's default user agent so Facebook serves the full desktop
/// Safari experience instead of an "unsupported browser" fallback.
const String kSafariUserAgentSuffix = 'Version/26.0 Safari/605.1.15';

/// Hosts that stay inside the app. Everything else opens in the default browser.
const List<String> kInAppDomains = [
  'facebook.com',
  'facebook.net',
  'fb.com',
  'fb.me',
  'fbcdn.net',
  'fbsbx.com',
  'messenger.com',
  'meta.com',
];

/// Facebook's outbound link shims (l.facebook.com/l.php?u=...).
const List<String> kLinkShimHosts = ['l.facebook.com', 'lm.facebook.com', 'l.messenger.com'];

const MethodChannel _shell = MethodChannel('kw_hab/shell');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FacebookApp());
}

class FacebookApp extends StatelessWidget {
  const FacebookApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Facebook',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0866FF)),
      ),
      home: const FacebookShell(),
    );
  }
}

// ---------------------------------------------------------------------------
// URL routing helpers
// ---------------------------------------------------------------------------

bool _isInAppHost(String host) {
  host = host.toLowerCase();
  return kInAppDomains.any((d) => host == d || host.endsWith('.$d'));
}

/// Returns the external destination for a link, or null if it should load in-app.
Uri? _externalTarget(Uri? uri) {
  if (uri == null) return null;
  final scheme = uri.scheme.toLowerCase();
  if (scheme.isEmpty || const ['about', 'data', 'blob', 'javascript'].contains(scheme)) {
    return null;
  }
  if (scheme != 'http' && scheme != 'https') {
    // mailto:, tel:, itms-apps:, etc.
    return uri;
  }
  if (kLinkShimHosts.contains(uri.host.toLowerCase())) {
    final target = uri.queryParameters['u'];
    final parsed = target == null ? null : Uri.tryParse(target);
    if (parsed != null && !_isInAppHost(parsed.host)) return parsed;
    return null;
  }
  return _isInAppHost(uri.host) ? null : uri;
}

Future<void> _openExternally(Uri uri) async {
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

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

// ---------------------------------------------------------------------------
// Main window
// ---------------------------------------------------------------------------

class FacebookShell extends StatefulWidget {
  const FacebookShell({super.key});

  @override
  State<FacebookShell> createState() => _FacebookShellState();
}

class _FacebookShellState extends State<FacebookShell> {
  InAppWebViewController? _controller;
  double _progress = 0;
  double _zoom = 1.0;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _shell.setMethodCallHandler(_onShellCall);
  }

  @override
  void dispose() {
    _shell.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> _onShellCall(MethodCall call) async {
    if (call.method != 'menu') return;
    final c = _controller;
    if (c == null) return;
    switch (call.arguments as String) {
      case 'reload':
        setState(() => _loadError = null);
        await c.reload();
      case 'back':
        if (await c.canGoBack()) await c.goBack();
      case 'forward':
        if (await c.canGoForward()) await c.goForward();
      case 'home':
        await c.loadUrl(urlRequest: URLRequest(url: WebUri(kHomeUrl)));
      case 'zoomIn':
        await _setZoom(_zoom + 0.1);
      case 'zoomOut':
        await _setZoom(_zoom - 0.1);
      case 'zoomReset':
        await _setZoom(1.0);
    }
  }

  Future<void> _setZoom(double zoom) async {
    _zoom = double.parse(zoom.clamp(0.5, 3.0).toStringAsFixed(2));
    await _controller?.setSettings(settings: InAppWebViewSettings(pageZoom: _zoom));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Positioned.fill(
            child: FacebookWebView(
              initialUrl: kHomeUrl,
              onCreated: (c) => _controller = c,
              onProgress: (p) => setState(() => _progress = p),
              onTitle: (t) {
                if (t != null && t.isNotEmpty) _shell.invokeMethod('setTitle', t);
              },
              onLoadStart: () {
                if (_loadError != null) setState(() => _loadError = null);
              },
              onMainFrameError: (message) => setState(() => _loadError = message),
            ),
          ),
          if (_progress < 1.0)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                value: _progress == 0 ? null : _progress,
                minHeight: 2,
                backgroundColor: Colors.transparent,
              ),
            ),
          if (_loadError != null)
            Positioned.fill(
              child: _ErrorOverlay(
                message: _loadError!,
                onRetry: () {
                  setState(() => _loadError = null);
                  _controller?.reload();
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ErrorOverlay extends StatelessWidget {
  const _ErrorOverlay({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF0F2F5),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 48, color: Color(0xFF65676B)),
            const SizedBox(height: 16),
            const Text(
              "Can't reach Facebook",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF65676B)),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared web view (used for the main window and for popup windows)
// ---------------------------------------------------------------------------

class FacebookWebView extends StatelessWidget {
  const FacebookWebView({
    super.key,
    this.initialUrl,
    this.windowId,
    this.onCreated,
    this.onProgress,
    this.onTitle,
    this.onLoadStart,
    this.onMainFrameError,
    this.onClose,
  });

  final String? initialUrl;

  /// Set when this web view backs a `window.open()` popup.
  final int? windowId;

  final ValueChanged<InAppWebViewController>? onCreated;
  final ValueChanged<double>? onProgress;
  final ValueChanged<String?>? onTitle;
  final VoidCallback? onLoadStart;
  final ValueChanged<String>? onMainFrameError;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      windowId: windowId,
      initialUrlRequest:
          initialUrl == null ? null : URLRequest(url: WebUri(initialUrl!)),
      initialSettings: _webViewSettings(),
      onWebViewCreated: onCreated,
      onLoadStart: (_, _) => onLoadStart?.call(),
      onProgressChanged: (_, p) => onProgress?.call(p / 100),
      onTitleChanged: (_, t) => onTitle?.call(t),
      onCloseWindow: (_) => onClose?.call(),
      shouldOverrideUrlLoading: (controller, action) async {
        if (!action.isForMainFrame) return NavigationActionPolicy.ALLOW;
        final external = _externalTarget(action.request.url);
        if (external == null) return NavigationActionPolicy.ALLOW;
        await _openExternally(external);
        return NavigationActionPolicy.CANCEL;
      },
      onCreateWindow: (controller, action) async {
        final external = _externalTarget(action.request.url);
        if (external != null) {
          await _openExternally(external);
          return false;
        }
        if (!context.mounted) return false;
        _showPopup(context, action.windowId);
        return true;
      },
      onPermissionRequest: (controller, request) async {
        final trusted = _isInAppHost(request.origin.host);
        return PermissionResponse(
          resources: request.resources,
          action: trusted ? PermissionResponseAction.GRANT : PermissionResponseAction.DENY,
        );
      },
      onDownloadStarting: (controller, request) {
        // WebKit's own download is cancelled natively; fetch it ourselves.
        if (context.mounted) _download(context, request);
        return DownloadStartResponse(handled: true);
      },
      onReceivedError: (controller, request, error) {
        if (request.isForMainFrame != true) return;
        // Cancelled navigations (e.g. links we sent to the browser) aren't errors.
        if (error.type == WebResourceErrorType.CANCELLED) return;
        if (error.description.contains('Frame load interrupted')) return;
        onMainFrameError?.call(error.description);
      },
    );
  }
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
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.centerRight,
                color: const Color(0xFFF0F2F5),
                child: IconButton(
                  tooltip: 'Close',
                  iconSize: 18,
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ),
              Expanded(
                child: FacebookWebView(
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

// ---------------------------------------------------------------------------
// Downloads
// ---------------------------------------------------------------------------

Future<void> _download(BuildContext context, DownloadStartRequest request) async {
  final messenger = ScaffoldMessenger.of(context);
  final url = request.url;
  try {
    final dir = await getDownloadsDirectory();
    if (dir == null) throw const FileSystemException('No Downloads folder');

    final name = _safeFileName(
      request.suggestedFilename ??
          (url.pathSegments.isNotEmpty ? url.pathSegments.last : 'download'),
    );
    final file = _uniqueFile(dir, name);

    if (url.scheme == 'data') {
      final data = UriData.fromUri(url);
      await file.writeAsBytes(data.contentAsBytes());
    } else if (url.scheme == 'http' || url.scheme == 'https') {
      messenger.showSnackBar(SnackBar(content: Text('Downloading $name…')));
      final client = HttpClient();
      try {
        final req = await client.getUrl(url);
        final cookies = await CookieManager.instance().getCookies(url: url);
        if (cookies.isNotEmpty) {
          req.headers.set(
            HttpHeaders.cookieHeader,
            cookies.map((c) => '${c.name}=${c.value}').join('; '),
          );
        }
        final res = await req.close();
        if (res.statusCode >= 400) {
          throw HttpException('HTTP ${res.statusCode}', uri: url);
        }
        await res.pipe(file.openWrite());
      } finally {
        client.close();
      }
    } else {
      throw UnsupportedError('This type of download (${url.scheme}:) isn\'t supported.');
    }

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Saved ${file.uri.pathSegments.last} to Downloads'),
        action: SnackBarAction(
          label: 'Show in Finder',
          onPressed: () => Process.run('open', ['-R', file.path]),
        ),
      ),
    );
  } catch (e) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text('Download failed: $e')));
  }
}

String _safeFileName(String name) {
  final cleaned = name.replaceAll(RegExp(r'[/\\:\x00-\x1F]'), '_').trim();
  return cleaned.isEmpty ? 'download' : cleaned;
}

File _uniqueFile(Directory dir, String name) {
  final dot = name.lastIndexOf('.');
  final base = dot > 0 ? name.substring(0, dot) : name;
  final ext = dot > 0 ? name.substring(dot) : '';
  var candidate = File('${dir.path}/$name');
  var i = 1;
  while (candidate.existsSync()) {
    candidate = File('${dir.path}/$base ($i)$ext');
    i++;
  }
  return candidate;
}
