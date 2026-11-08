import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../injections/injection_bundle.dart';
import '../screens/onboarding/onboarding_screen.dart';
import '../settings/app_settings.dart';
import '../settings/open_settings_bridge.dart';
import 'facebook_web_view.dart';
import 'login_state.dart';
import 'native_shell.dart';
import 'page_bridge.dart';
import 'url_routing.dart';

/// The main window: the Facebook web view plus a loading bar and offline screen.
///
/// Also shows [OnboardingScreen] after the first Facebook login (until it has
/// been finished once), and again from the Settings… menu item (⌘,) or the
/// Settings item in Facebook's profile menu ([OpenSettingsBridge]).
class FacebookShell extends StatefulWidget {
  const FacebookShell({
    super.key,
    required this.injections,
    required this.settings,
    this.bridges = const [],
  });

  final InjectionBundle injections;
  final AppSettings settings;
  final List<PageBridge> bridges;

  @override
  State<FacebookShell> createState() => _FacebookShellState();
}

class _FacebookShellState extends State<FacebookShell> {
  InAppWebViewController? _controller;
  double _progress = 0;
  double _zoom = 1.0;
  String? _loadError;
  bool _onboardingOpen = false;

  @override
  void initState() {
    super.initState();
    NativeShell.onMenuCommand(_onMenuCommand);
    for (final b in widget.bridges.whereType<OpenSettingsBridge>()) {
      b.onOpen = _openSettings;
    }
  }

  void _openSettings() => _showOnboarding(firstRun: !widget.settings.onboardingComplete);

  @override
  void dispose() {
    NativeShell.onMenuCommand(null);
    for (final b in widget.bridges.whereType<OpenSettingsBridge>()) {
      if (b.onOpen == _openSettings) b.onOpen = null;
    }
    super.dispose();
  }

  Future<void> _onMenuCommand(String command) async {
    final c = _controller;
    if (c == null) return;
    switch (command) {
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
      case 'settings':
        _openSettings();
    }
  }

  /// After each page load: if someone is logged in to Facebook and onboarding
  /// was never finished, show it. Covers logging in, finishing sign-up, and
  /// launching while already logged in.
  Future<void> _checkOnboarding() async {
    if (widget.settings.onboardingComplete || _onboardingOpen) return;
    final c = _controller;
    if (c == null || !await isLoggedIn(c)) return;
    if (!mounted || widget.settings.onboardingComplete) return;
    await _showOnboarding(firstRun: true);
  }

  Future<void> _showOnboarding({required bool firstRun}) async {
    if (_onboardingOpen) return;
    _onboardingOpen = true;
    try {
      await OnboardingScreen.show(context, firstRun: firstRun);
    } finally {
      _onboardingOpen = false;
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
              injections: widget.injections,
              bridges: widget.bridges,
              initialUrl: kHomeUrl,
              onCreated: (c) => _controller = c,
              onProgress: (p) => setState(() => _progress = p),
              onTitle: (t) {
                if (t != null && t.isNotEmpty) NativeShell.setTitle(t);
              },
              onLoadStart: () {
                if (_loadError != null) setState(() => _loadError = null);
              },
              onLoadStop: (_) => _checkOnboarding(),
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
