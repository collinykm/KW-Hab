import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'app.dart';
import 'cloudinary/cloudinary_bridges.dart';
import 'injections/injection_bundle.dart';
import 'monitoring/monitoring_setup.dart';
import 'shell/page_bridge.dart';
import 'speech/speech_bridge.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  final injections = await InjectionBundle.load(rootBundle);
  final cloudinary = createCloudinaryClient();
  // Dart services page scripts can call (see lib/shell/page_bridge.dart).
  final bridges = <PageBridge>[
    ?createMessageMonitorBridge(),
    createReadAloudBridge(),
    createSpeechToTextBridge(),
    PostSummaryBridge(cloudinary),
    PhotoFixBridge(cloudinary),
  ];
  runApp(FacebookApp(injections: injections, bridges: bridges));
}
