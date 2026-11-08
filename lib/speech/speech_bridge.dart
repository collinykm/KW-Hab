import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../shell/page_bridge.dart';
import '../shell/url_routing.dart';
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
class ReadAloudBridge implements PageBridge {
  ReadAloudBridge(this.tts);

  /// Must match the handler name in read-aloud.js.
  static const String handlerName = 'kwReadAloud';

  final ElevenLabsTts tts;

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
ReadAloudBridge createReadAloudBridge() {
  const names = ['ELEVENLABS_API_KEY', 'ELEVENLABS_VOICE_ID', 'ELEVENLABS_MODEL_ID'];
  final settings = <String, String>{};
  for (final name in names) {
    final fromFile = dotenv.isInitialized ? dotenv.get(name, fallback: '').trim() : '';
    final value = fromFile.isNotEmpty ? fromFile : (Platform.environment[name] ?? '').trim();
    if (value.isNotEmpty) settings[name] = value;
  }
  final tts = ElevenLabsTts.fromEnvironment(settings);
  debugPrint(tts.isConfigured
      ? '[kw-hab:read-aloud] on, voice ${tts.voiceId}, model ${tts.modelId}'
      : '[kw-hab:read-aloud] off: no ELEVENLABS_API_KEY in .env or the environment');
  return ReadAloudBridge(tts);
}
