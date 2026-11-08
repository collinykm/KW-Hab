import 'package:flutter/material.dart';

import 'injections/injection_bundle.dart';
import 'settings/accessibility_theme.dart';
import 'settings/app_settings.dart';
import 'settings/settings_scope.dart';
import 'shell/facebook_shell.dart';
import 'shell/page_bridge.dart';

/// Root widget. Native Flutter screens (e.g. onboarding under `lib/screens/`)
/// are pushed over [FacebookShell] from here or from the shell.
///
/// [settings] is provided to every widget through [SettingsScope], and its
/// accessibility choices (text size, bold, button size) are applied to all
/// Flutter screens here.
class FacebookApp extends StatelessWidget {
  const FacebookApp({
    super.key,
    required this.injections,
    required this.settings,
    this.bridges = const [],
  });

  final InjectionBundle injections;
  final AppSettings settings;
  final List<PageBridge> bridges;

  @override
  Widget build(BuildContext context) {
    return SettingsScope(
      settings: settings,
      child: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => MaterialApp(
          title: 'KW Connect',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(settings.accessibility),
          builder: (context, child) =>
              applyAccessibilityMediaQuery(context, settings.accessibility, child!),
          home: FacebookShell(injections: injections, bridges: bridges, settings: settings),
        ),
      ),
    );
  }
}
