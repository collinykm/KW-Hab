import 'package:flutter_test/flutter_test.dart';
import 'package:kw_hab/speech/eleven_labs_tts.dart';

void main() {
  test('is not configured without ELEVENLABS_API_KEY', () async {
    final tts = ElevenLabsTts.fromEnvironment({});
    expect(tts.isConfigured, isFalse);
    expect(
      () => tts.synthesize('hello'),
      throwsA(isA<SpeechException>().having((e) => e.code, 'code', 'not_configured')),
    );
  });

  test('treats a blank key as missing and trims values', () {
    expect(ElevenLabsTts.fromEnvironment({'ELEVENLABS_API_KEY': '   '}).isConfigured, isFalse);
    final tts = ElevenLabsTts.fromEnvironment({
      'ELEVENLABS_API_KEY': ' key ',
      'ELEVENLABS_VOICE_ID': ' voice ',
    });
    expect(tts.apiKey, 'key');
    expect(tts.voiceId, 'voice');
    expect(tts.modelId, ElevenLabsTts.defaultModelId);
  });

  test('rejects empty text before calling the API', () {
    final tts = ElevenLabsTts(apiKey: 'key');
    expect(
      () => tts.synthesize('   '),
      throwsA(isA<SpeechException>().having((e) => e.code, 'code', 'empty')),
    );
  });
}
