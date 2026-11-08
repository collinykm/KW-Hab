import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../settings/app_settings.dart';
import '../settings/support_contact.dart';

import 'alert_channels.dart';
import 'delivering_staff_notifier.dart';
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
/// - `TWILIO_ACCOUNT_SID` (`AC…`), `TWILIO_FROM` (a Twilio number like
///   `+15195550123`, or an `MG…` Messaging Service SID), and either
///   `TWILIO_API_KEY_SID` (`SK…`) + `TWILIO_API_KEY_SECRET` or
///   `TWILIO_AUTH_TOKEN` (optional; together they turn on SMS alerts)
/// - `RESEND_API_KEY` (optional, turns on email alerts) and `RESEND_FROM`
///   (optional, defaults to [ResendEmailChannel.defaultFrom])
///
/// Without SMS or email keys, alerts are only printed to the console.
///
/// Bundled assets can be read out of the built app, so this is for
/// development only; a release should call Gemini, Twilio and Resend through
/// a server of ours.
/// Alerts go to the support people in [settings] (entered during onboarding).
MessageMonitorBridge? createMessageMonitorBridge(AppSettings settings) {
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
    notifier: _createNotifier(settings),
  ));
}

StaffNotifier _createNotifier(AppSettings settings) {
  String env(String name) => dotenv.get(name, fallback: '').trim();

  // A service with only some of its keys (or the wrong ones) is almost
  // certainly a mistake, and would otherwise quietly send everything the
  // other way.
  final twilio = twilioConfigProblem(
    accountSid: env('TWILIO_ACCOUNT_SID'),
    authToken: env('TWILIO_AUTH_TOKEN'),
    apiKeySid: env('TWILIO_API_KEY_SID'),
    apiKeySecret: env('TWILIO_API_KEY_SECRET'),
    from: env('TWILIO_FROM'),
  );
  if (twilio != null && twilio.isNotEmpty) {
    debugPrint('[kw-hab:message-monitor] SMS alerts OFF: $twilio');
  }
  if (env('RESEND_FROM').isNotEmpty && env('RESEND_API_KEY').isEmpty) {
    debugPrint('[kw-hab:message-monitor] email alerts OFF: .env is missing RESEND_API_KEY');
  }

  final channels = <AlertChannel>[
    if (twilio == null)
      TwilioSmsChannel(
        accountSid: env('TWILIO_ACCOUNT_SID'),
        authToken: env('TWILIO_AUTH_TOKEN'),
        apiKeySid: env('TWILIO_API_KEY_SID'),
        apiKeySecret: env('TWILIO_API_KEY_SECRET'),
        from: env('TWILIO_FROM'),
      ),
    if (env('RESEND_API_KEY').isNotEmpty)
      ResendEmailChannel(
        apiKey: env('RESEND_API_KEY'),
        from: env('RESEND_FROM').isEmpty ? ResendEmailChannel.defaultFrom : env('RESEND_FROM'),
      ),
  ];
  if (channels.isEmpty) {
    debugPrint('[kw-hab:message-monitor] no Twilio or Resend keys in .env: '
        'alerts are printed here instead of sent');
    return ConsoleStaffNotifier(settings);
  }
  debugPrint('[kw-hab:message-monitor] alerts by '
      '${channels.map((c) => c.method == ContactMethod.phone ? 'SMS' : 'email').join(' and ')}');
  return DeliveringStaffNotifier(settings: settings, channels: channels);
}

/// Why the Twilio settings can't work: null when they're fine, '' when none
/// are set (SMS is just off), otherwise what to fix. Public for tests.
String? twilioConfigProblem({
  required String accountSid,
  required String authToken,
  required String apiKeySid,
  required String apiKeySecret,
  required String from,
}) {
  if ([accountSid, authToken, apiKeySid, apiKeySecret, from].every((v) => v.isEmpty)) return '';
  final problems = <String>[
    if (accountSid.isEmpty)
      'TWILIO_ACCOUNT_SID is missing (the AC… Account SID)'
    else if (accountSid.startsWith('SK'))
      'TWILIO_ACCOUNT_SID is an API key (SK…): put it in TWILIO_API_KEY_SID and '
          'use the AC… Account SID here'
    else if (!accountSid.startsWith('AC'))
      'TWILIO_ACCOUNT_SID should start with AC',
    if (apiKeySid.isEmpty && authToken.isEmpty)
      'set TWILIO_API_KEY_SID + TWILIO_API_KEY_SECRET, or TWILIO_AUTH_TOKEN',
    if (apiKeySid.isNotEmpty && apiKeySecret.isEmpty) 'TWILIO_API_KEY_SECRET is missing',
    if (from.isEmpty)
      'TWILIO_FROM is missing (your Twilio number, like +15195550123)'
    else if (!from.startsWith('MG') && !RegExp(r'^\+\d{8,15}$').hasMatch(from))
      'TWILIO_FROM should be your Twilio number written like +15195550123',
  ];
  return problems.isEmpty ? null : problems.join('; ');
}
