import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'app.dart';
import 'injections/injection_bundle.dart';
import 'monitoring/monitoring_setup.dart';
import 'settings/app_settings.dart';
import 'settings/page_settings_bridge.dart';
import 'shell/page_bridge.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  // User settings (accessibility, support contacts); see lib/settings/.
  final settings = AppSettings();
  await settings.load();
  final injections = await InjectionBundle.load(rootBundle);
  // Dart services page scripts can call (see lib/shell/page_bridge.dart).
  final bridges = <PageBridge>[
    PageSettingsBridge(settings),
    ?createMessageMonitorBridge(settings),
  ];
  runApp(FacebookApp(injections: injections, settings: settings, bridges: bridges));
}
