import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../settings/app_settings.dart';

import 'gemini_safety_classifier.dart';
import 'message_monitor.dart';
import 'message_monitor_bridge.dart';
import 'staff_notifier.dart';

/// Builds the message monitor from `.env`, or returns null (with a console
/// note) when no Gemini key is set.
///
/// `.env` is git-ignored and bundled as an asset (copy `.env.example`):
/// - `GEMINI_API_KEY` (required to turn monitoring on)
/// - `GEMINI_MODEL` (optional, defaults to [GeminiSafetyClassifier.defaultModel])
///
/// Bundled assets can be read out of the built app, so this is for
/// development only; a release should call Gemini through a server of ours.
/// Alerts go to the support people in [settings] (entered during onboarding).
MessageMonitorBridge? createMessageMonitorBridge(AppSettings settings) {
  final apiKey = dotenv.get('GEMINI_API_KEY', fallback: '').trim();
  final model = dotenv.get('GEMINI_MODEL', fallback: '').trim();
  if (apiKey.isEmpty) {
    debugPrint('[kw-hab:message-monitor] off: no GEMINI_API_KEY in .env');
    return null;
  }
  debugPrint('[kw-hab:message-monitor] on, using '
      '${model.isEmpty ? GeminiSafetyClassifier.defaultModel : model}');
  return MessageMonitorBridge(MessageMonitor(
    classifier: GeminiSafetyClassifier(
      apiKey: apiKey,
      model: model.isEmpty ? GeminiSafetyClassifier.defaultModel : model,
    ),
    // TODO: replace with real SMS/email delivery to the same recipients.
    notifier: ConsoleStaffNotifier(settings),
  ));
}
