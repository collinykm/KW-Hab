import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'gemini_safety_classifier.dart';
import 'message_monitor.dart';
import 'message_monitor_bridge.dart';
import 'staff_notifier.dart';

/// Builds the message monitor from `.env`, or returns null (with a console
/// note) when no Gemini key is set.
///
/// `.env` is git-ignored and bundled as an asset:
/// - `GEMINI_API_KEY` (required to turn monitoring on)
/// - `GEMINI_MODEL` (optional, defaults to [GeminiSafetyClassifier.defaultModel])
/// - `GEMINI_FALLBACK_MODELS` (optional, comma-separated, tried in order when
///   the main model is rate limited; defaults to
///   [GeminiSafetyClassifier.defaultFallbackModels])
///
/// Bundled assets can be read out of the built app, so this is for
/// development only; a release should call Gemini through a server of ours.
MessageMonitorBridge? createMessageMonitorBridge() {
  final apiKey = dotenv.get('GEMINI_API_KEY', fallback: '').trim();
  final setModel = dotenv.get('GEMINI_MODEL', fallback: '').trim();
  final model = setModel.isEmpty ? GeminiSafetyClassifier.defaultModel : setModel;
  final setFallbacks = [
    for (final m in dotenv.get('GEMINI_FALLBACK_MODELS', fallback: '').split(','))
      if (m.trim().isNotEmpty) m.trim()
  ];
  final fallbacks =
      setFallbacks.isEmpty ? GeminiSafetyClassifier.defaultFallbackModels : setFallbacks;
  if (apiKey.isEmpty) {
    debugPrint('[kw-hab:message-monitor] off: no GEMINI_API_KEY in .env');
    return null;
  }
  debugPrint('[kw-hab:message-monitor] on, using $model '
      '(fallbacks: ${fallbacks.join(', ')})');
  return MessageMonitorBridge(MessageMonitor(
    classifier: GeminiSafetyClassifier(
      apiKey: apiKey,
      model: model,
      fallbackModels: fallbacks,
    ),
    // TODO: replace with SMS/email delivery once onboarding collects the
    // support worker's contact and preferred method.
    notifier: ConsoleStaffNotifier(),
  ));
}
