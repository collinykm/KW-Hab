import 'package:flutter/material.dart';

import 'injections/injection_bundle.dart';
import 'shell/facebook_shell.dart';
import 'shell/page_bridge.dart';

/// Root widget. Native Flutter screens (e.g. a custom login/onboarding flow
/// under `lib/screens/`) should be routed from here, before [FacebookShell].
class FacebookApp extends StatelessWidget {
  const FacebookApp({super.key, required this.injections, this.bridges = const []});

  final InjectionBundle injections;
  final List<PageBridge> bridges;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Facebook',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0866FF)),
      ),
      home: FacebookShell(injections: injections, bridges: bridges),
    );
  }
}
