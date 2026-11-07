import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'injections/injection_bundle.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final injections = await InjectionBundle.load(rootBundle);
  runApp(FacebookApp(injections: injections));
}
