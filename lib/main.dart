import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'app.dart';
import 'cloudinary/cloudinary_bridges.dart';
import 'injections/injection_bundle.dart';
import 'monitoring/monitoring_setup.dart';
import 'settings/app_settings.dart';
import 'settings/open_settings_bridge.dart';
import 'settings/page_settings_bridge.dart';
import 'shell/page_bridge.dart';
import 'shell/platform.dart';
import 'speech/speech_bridge.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  // User settings (accessibility, support contacts); see lib/settings/.
  final settings = AppSettings();
  await settings.load();
  final injections = await InjectionBundle.load(rootBundle);
  // Phones/tablets: ask Facebook for its desktop site (see
  // lib/shell/platform.dart). Android debug builds can be inspected from
  // chrome://inspect (iOS and macOS use isInspectable).
  await loadMobileDesktopUserAgent();
  if (isAndroid) await InAppWebViewController.setWebContentsDebuggingEnabled(kDebugMode);
  final cloudinary = createCloudinaryClient();
  // Dart services page scripts can call (see lib/shell/page_bridge.dart).
  final bridges = <PageBridge>[
    PageSettingsBridge(settings),
    OpenSettingsBridge(),
    ?createMessageMonitorBridge(settings),
    createReadAloudBridge(settings),
    createSpeechToTextBridge(settings),
    PostSummaryBridge(cloudinary),
  ];
  runApp(FacebookApp(injections: injections, settings: settings, bridges: bridges));
}
