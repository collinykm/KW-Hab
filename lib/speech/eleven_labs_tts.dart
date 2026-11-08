import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Text-to-speech through the ElevenLabs API.
///
/// The API key is read from the `ELEVENLABS_API_KEY` environment variable when
/// the app starts, so it never lives in the repository, the build, or the
/// Facebook page. Optional overrides: `ELEVENLABS_VOICE_ID`,
/// `ELEVENLABS_MODEL_ID`.
class ElevenLabsTts {
  ElevenLabsTts({
    required this.apiKey,
    this.voiceId = defaultVoiceId,
    this.modelId = defaultModelId,
  });

  factory ElevenLabsTts.fromEnvironment([Map<String, String>? environment]) {
    final env = environment ?? Platform.environment;
    String? value(String name) {
      final v = env[name]?.trim();
      return (v == null || v.isEmpty) ? null : v;
    }

    return ElevenLabsTts(
      apiKey: value('ELEVENLABS_API_KEY'),
      voiceId: value('ELEVENLABS_VOICE_ID') ?? defaultVoiceId,
      modelId: value('ELEVENLABS_MODEL_ID') ?? defaultModelId,
    );
  }

  /// A premade ElevenLabs voice. Override with `ELEVENLABS_VOICE_ID`.
  static const String defaultVoiceId = 'JBFqnCBsd6RMkjVDRZzb';

  /// ElevenLabs' lifelike model: natural-sounding and nearly as quick to start
  /// as `eleven_flash_v2_5` (which sounds flat and robotic). `eleven_v4` is
  /// more expressive but takes about a second longer.
  static const String defaultModelId = 'eleven_multilingual_v2';

  /// Slightly below ElevenLabs' default stability (0.5) for a warmer, less
  /// monotone read; the rest are ElevenLabs' defaults.
  static const Map<String, Object> voiceSettings = {
    'stability': 0.4,
    'similarity_boost': 0.75,
    'style': 0,
    'use_speaker_boost': true,
    'speed': 1.0,
  };

  /// Longer text is cut off, to keep each request (and its cost) bounded.
  static const int maxCharacters = 2500;

  static const Duration timeout = Duration(seconds: 20);

  final String? apiKey;
  final String voiceId;
  final String modelId;

  bool get isConfigured => apiKey != null;

  /// Returns MP3 audio for [text].
  Future<Uint8List> synthesize(String text) async {
    final key = apiKey;
    if (key == null) {
      throw const SpeechException('not_configured', 'ELEVENLABS_API_KEY is not set');
    }
    var input = text.trim();
    if (input.isEmpty) throw const SpeechException('empty', 'Nothing to read');
    if (input.length > maxCharacters) input = input.substring(0, maxCharacters);

    final uri = Uri.https(
      'api.elevenlabs.io',
      '/v1/text-to-speech/$voiceId',
      {'output_format': 'mp3_44100_128'},
    );
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.postUrl(uri).timeout(timeout);
      request.headers
        ..set('xi-api-key', key)
        ..contentType = ContentType.json
        ..set(HttpHeaders.acceptHeader, 'audio/mpeg');
      request.add(utf8.encode(jsonEncode({
        'text': input,
        'model_id': modelId,
        'voice_settings': voiceSettings,
      })));
      final response = await request.close().timeout(timeout);
      final bytes = await response
          .fold<BytesBuilder>(BytesBuilder(copy: false), (b, chunk) => b..add(chunk))
          .timeout(timeout);
      if (response.statusCode != 200) {
        // The body is a JSON error from ElevenLabs; it never contains the key.
        throw SpeechException(
          response.statusCode == 401 ? 'unauthorized' : 'http_${response.statusCode}',
          utf8.decode(bytes.takeBytes(), allowMalformed: true),
        );
      }
      return bytes.takeBytes();
    } on SocketException catch (e) {
      throw SpeechException('network', e.message);
    } on HttpException catch (e) {
      throw SpeechException('network', e.message);
    } on TimeoutException {
      throw const SpeechException('timeout', 'ElevenLabs did not respond in time');
    } finally {
      client.close(force: true);
    }
  }
}

class SpeechException implements Exception {
  const SpeechException(this.code, this.message);

  /// Short machine-readable reason, passed to the page (never the key).
  final String code;
  final String message;

  @override
  String toString() => 'SpeechException($code): $message';
}
