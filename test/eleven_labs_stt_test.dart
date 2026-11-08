import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kw_hab/speech/eleven_labs_stt.dart';
import 'package:kw_hab/speech/eleven_labs_tts.dart' show SpeechException;

Matcher speechError(String code) =>
    throwsA(isA<SpeechException>().having((e) => e.code, 'code', code));

void main() {
  final audio = Uint8List.fromList([1, 2, 3, 4]);

  test('sends the recording and returns the transcript', () async {
    late http.Request sent;
    final stt = ElevenLabsStt(
      apiKey: 'test-key',
      client: MockClient((request) async {
        sent = request;
        return http.Response('{"text":" Hello there. ","language_code":"eng"}', 200);
      }),
    );

    expect(await stt.transcribe(audio, 'audio/webm;codecs=opus'), 'Hello there.');
    expect(sent.url, ElevenLabsStt.endpoint);
    expect(sent.headers['xi-api-key'], 'test-key');
    expect(sent.url.query, isNot(contains('test-key')));
    expect(sent.headers['content-type'], startsWith('multipart/form-data'));
    final body = String.fromCharCodes(sent.bodyBytes);
    expect(body, contains('name="model_id"\r\n\r\nscribe_v2'));
    expect(body, contains('name="tag_audio_events"\r\n\r\nfalse'));
    expect(body, contains('name="file"; filename="speech.webm"'));
  });

  test('refuses without a key, empty or unknown audio, and oversized recordings', () async {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response('{}', 200);
    });
    expect(ElevenLabsStt(apiKey: null, client: client).transcribe(audio, 'audio/webm'),
        speechError('not_configured'));
    final stt = ElevenLabsStt(apiKey: 'k', client: client);
    expect(stt.transcribe(Uint8List(0), 'audio/webm'), speechError('empty'));
    expect(stt.transcribe(audio, 'text/html'), speechError('bad_audio'));
    expect(stt.transcribe(Uint8List(ElevenLabsStt.maxBytes + 1), 'audio/mp4'),
        speechError('too_long'));
    await Future<void>.delayed(Duration.zero);
    expect(requests, 0);
  });

  test('maps HTTP errors to codes', () async {
    final stt = ElevenLabsStt(
      apiKey: 'k',
      client: MockClient((_) async => http.Response('{"detail":"bad key"}', 401)),
    );
    await expectLater(stt.transcribe(audio, 'audio/mp4'), speechError('unauthorized'));
  });

  test('parses transcripts', () {
    expect(ElevenLabsStt.parseTranscript('{"text":"hi"}'), 'hi');
    expect(() => ElevenLabsStt.parseTranscript('{"words":[]}'), speechError('bad_response'));
    expect(() => ElevenLabsStt.parseTranscript('nope'), speechError('bad_response'));
  });
}
