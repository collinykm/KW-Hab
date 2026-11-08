import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../settings/app_settings.dart';
import '../shell/page_bridge.dart';
import '../shell/url_routing.dart';
import 'eleven_labs_stt.dart';
import 'eleven_labs_tts.dart';

/// Lets `assets/injections/js/read-aloud.js` ask for speech:
///
/// ```js
/// window.flutter_inappwebview.callHandler('kwReadAloud', text)
///   // -> {ok: true, mimeType, audio: base64} or {ok: false, error: code}
/// ```
///
/// The ElevenLabs request happens here on the Dart side, so the page only
/// ever sees audio, never the API key.
///
/// Refuses with `disabled` while [isEnabled] is false (the user's "Read text
/// aloud" setting), so nothing in the page can use it when it is turned off.
class ReadAloudBridge extends PageBridge {
  ReadAloudBridge(this.tts, {bool Function()? isEnabled}) : isEnabled = isEnabled ?? _always;

  /// Must match the handler name in read-aloud.js.
  static const String handlerName = 'kwReadAloud';

  final ElevenLabsTts tts;
  final bool Function() isEnabled;

  @override
  void attach(InAppWebViewController controller) {
    controller.addJavaScriptHandler(
      handlerName: handlerName,
      callback: (JavaScriptHandlerFunctionData data) async {
        // Only Facebook's own top-level page, so embedded third-party frames
        // can't spend the ElevenLabs credits.
        if (!data.isMainFrame || !isInAppHost(data.origin.host)) {
          return {'ok': false, 'error': 'not_allowed'};
        }
        if (!isEnabled()) return {'ok': false, 'error': 'disabled'};
        final text = data.args.isEmpty ? null : data.args.first;
        if (text is! String || text.trim().isEmpty) {
          return {'ok': false, 'error': 'empty'};
        }
        if (!tts.isConfigured) return {'ok': false, 'error': 'not_configured'};
        try {
          final audio = await tts.synthesize(text);
          return {'ok': true, 'mimeType': 'audio/mpeg', 'audio': base64Encode(audio)};
        } on SpeechException catch (e) {
          debugPrint('[kw-hab:read-aloud] $e');
          return {'ok': false, 'error': e.code};
        }
      },
    );
  }
}

/// Always returns a bridge, so the page can say "Read aloud isn't set up yet"
/// instead of failing silently when there is no key.
///
/// The key comes from `.env` (git-ignored, see `.env.example`) or, failing
/// that, from the `ELEVENLABS_API_KEY` environment variable. Optional:
/// `ELEVENLABS_VOICE_ID`, `ELEVENLABS_MODEL_ID`.
///
/// Only works while the user has "Read text aloud" on in [appSettings].
ReadAloudBridge createReadAloudBridge(AppSettings appSettings) {
  final settings = _elevenLabsSettings(
      const ['ELEVENLABS_API_KEY', 'ELEVENLABS_VOICE_ID', 'ELEVENLABS_MODEL_ID']);
  final tts = ElevenLabsTts.fromEnvironment(settings);
  debugPrint(tts.isConfigured
      ? '[kw-hab:read-aloud] on, voice ${tts.voiceId}, model ${tts.modelId}'
      : '[kw-hab:read-aloud] off: no ELEVENLABS_API_KEY in .env or the environment');
  return ReadAloudBridge(tts, isEnabled: () => appSettings.accessibility.readAloud);
}

/// Lets `assets/injections/js/speech-to-text.js` turn a recording into text:
///
/// ```js
/// window.flutter_inappwebview.callHandler('kwSpeechToText', base64Audio, mimeType)
///   // -> {ok: true, text} or {ok: false, error: code}
/// ```
///
/// Like read aloud, the ElevenLabs request happens here, so the page never
/// sees the API key.
///
/// Refuses with `disabled` while [isEnabled] is false (the user's "Talk to
/// type" setting).
class SpeechToTextBridge extends PageBridge {
  SpeechToTextBridge(this.stt, {bool Function()? isEnabled}) : isEnabled = isEnabled ?? _always;

  /// Must match `HANDLER` in speech-to-text.js.
  static const String handlerName = 'kwSpeechToText';

  final ElevenLabsStt stt;
  final bool Function() isEnabled;

  @override
  void attach(InAppWebViewController controller) {
    controller.addJavaScriptHandler(
      handlerName: handlerName,
      callback: (JavaScriptHandlerFunctionData data) async {
        // Only Facebook's own top-level page, so embedded third-party frames
        // can't spend the ElevenLabs credits.
        if (!data.isMainFrame || !isInAppHost(data.origin.host)) {
          return {'ok': false, 'error': 'not_allowed'};
        }
        if (!isEnabled()) return {'ok': false, 'error': 'disabled'};
        if (!stt.isConfigured) return {'ok': false, 'error': 'not_configured'};
        final args = data.args;
        if (args.length < 2 || args[0] is! String || args[1] is! String) {
          return {'ok': false, 'error': 'bad_audio'};
        }
        final encoded = args[0] as String;
        // Base64 is 4/3 the size of the audio: refuse before decoding.
        if (encoded.length > ElevenLabsStt.maxBytes * 4 ~/ 3 + 4) {
          return {'ok': false, 'error': 'too_long'};
        }
        final Uint8List audio;
        try {
          audio = base64Decode(encoded);
        } on FormatException {
          return {'ok': false, 'error': 'bad_audio'};
        }
        try {
          return {'ok': true, 'text': await stt.transcribe(audio, args[1] as String)};
        } on SpeechException catch (e) {
          debugPrint('[kw-hab:speech-to-text] $e');
          return {'ok': false, 'error': e.code};
        }
      },
    );
  }
}

/// Always returns a bridge, so the page can say "Speech to text isn't set up
/// yet" when there is no key. Uses `ELEVENLABS_API_KEY` like read aloud;
/// optional `ELEVENLABS_STT_MODEL_ID`.
///
/// Only works while the user has "Talk to type" on in [appSettings].
SpeechToTextBridge createSpeechToTextBridge(AppSettings appSettings) {
  final settings =
      _elevenLabsSettings(const ['ELEVENLABS_API_KEY', 'ELEVENLABS_STT_MODEL_ID']);
  final stt = ElevenLabsStt(
    apiKey: settings['ELEVENLABS_API_KEY'],
    modelId: settings['ELEVENLABS_STT_MODEL_ID'] ?? ElevenLabsStt.defaultModelId,
  );
  debugPrint(stt.isConfigured
      ? '[kw-hab:speech-to-text] on, model ${stt.modelId}'
      : '[kw-hab:speech-to-text] off: no ELEVENLABS_API_KEY in .env or the environment');
  return SpeechToTextBridge(stt, isEnabled: () => appSettings.accessibility.talkToType);
}

/// Non-empty values for [names], from `.env` (git-ignored) or, failing that,
/// the environment.
Map<String, String> _elevenLabsSettings(List<String> names) {
  final settings = <String, String>{};
  for (final name in names) {
    final fromFile = dotenv.isInitialized ? dotenv.get(name, fallback: '').trim() : '';
    final value = fromFile.isNotEmpty ? fromFile : (Platform.environment[name] ?? '').trim();
    if (value.isNotEmpty) settings[name] = value;
  }
  return settings;
}

bool _always() => true;
