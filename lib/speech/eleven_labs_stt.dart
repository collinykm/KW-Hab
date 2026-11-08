import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'eleven_labs_tts.dart' show SpeechException;

/// Speech-to-text through the ElevenLabs API (Scribe).
///
/// Uses the same `ELEVENLABS_API_KEY` as read aloud; the key stays on the Dart
/// side. Optional override: `ELEVENLABS_STT_MODEL_ID`.
class ElevenLabsStt {
  ElevenLabsStt({
    required this.apiKey,
    this.modelId = defaultModelId,
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// ElevenLabs' batch transcription model for recorded clips.
  static const String defaultModelId = 'scribe_v2';

  /// Recordings stop after a minute (see speech-to-text.js); this leaves room
  /// for less efficient formats while keeping Facebook's scripts from sending
  /// us anything huge.
  static const int maxBytes = 10 * 1024 * 1024;

  static const Duration timeout = Duration(seconds: 30);

  /// Formats a browser's MediaRecorder produces (WebKit: mp4; Chromium: webm),
  /// and the file extension each is sent with.
  static const Map<String, String> _extensions = {
    'audio/webm': 'webm',
    'audio/mp4': 'm4a',
    'audio/ogg': 'ogg',
    'audio/mpeg': 'mp3',
    'audio/wav': 'wav',
    'audio/aac': 'aac',
  };

  static final Uri endpoint = Uri.https('api.elevenlabs.io', '/v1/speech-to-text');

  final String? apiKey;
  final String modelId;
  final http.Client _client;

  bool get isConfigured => apiKey != null;

  /// Returns what was said in [audio], or an empty string if nothing was.
  /// [mimeType] may carry parameters (`audio/webm;codecs=opus`).
  Future<String> transcribe(Uint8List audio, String mimeType) async {
    final key = apiKey;
    if (key == null) {
      throw const SpeechException('not_configured', 'ELEVENLABS_API_KEY is not set');
    }
    final type = mimeType.split(';').first.trim().toLowerCase();
    if (!_extensions.containsKey(type)) {
      throw SpeechException('bad_audio', 'unsupported audio type $type');
    }
    if (audio.isEmpty) throw const SpeechException('empty', 'No audio');
    if (audio.length > maxBytes) {
      throw const SpeechException('too_long', 'Recording is too large');
    }

    final request = http.MultipartRequest('POST', endpoint)
      ..headers['xi-api-key'] = key
      ..fields['model_id'] = modelId
      // No "(laughter)"-style tags in text that gets typed for the user.
      ..fields['tag_audio_events'] = 'false'
      // ElevenLabs works out the format from the audio (and the extension).
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        audio,
        filename: 'speech.${_extensions[type]}',
      ));

    final http.Response response;
    try {
      response = await http.Response.fromStream(
          await _client.send(request).timeout(timeout));
    } on TimeoutException {
      throw const SpeechException('timeout', 'ElevenLabs did not respond in time');
    } catch (e) {
      throw SpeechException('network', '$e');
    }
    if (response.statusCode != 200) {
      // The body is a JSON error from ElevenLabs; it never contains the key.
      throw SpeechException(
        response.statusCode == 401 ? 'unauthorized' : 'http_${response.statusCode}',
        response.body.length > 300 ? response.body.substring(0, 300) : response.body,
      );
    }
    return parseTranscript(response.body);
  }

  /// Reads the transcript out of a response. Public for tests.
  static String parseTranscript(String body) {
    try {
      final text = (jsonDecode(body) as Map)['text'];
      if (text is String) return text.trim();
    } catch (_) {}
    throw const SpeechException('bad_response', 'response has no transcript');
  }
}
