import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kw_hab/monitoring/conversation.dart';
import 'package:kw_hab/monitoring/gemini_safety_classifier.dart';
import 'package:kw_hab/monitoring/message_monitor.dart';
import 'package:kw_hab/monitoring/safety_classifier.dart';
import 'package:kw_hab/monitoring/staff_notifier.dart';

ConversationSnapshot snapshot(List<(bool, String)> messages, {String id = 'thread:1'}) =>
    ConversationSnapshot(
      conversationId: id,
      title: 'Sam',
      messages: [for (final (fromUser, text) in messages) MonitoredMessage(fromUser: fromUser, text: text)],
    );

const safe = SafetyAssessment(
  notifyStaff: false,
  category: ConcernCategory.none,
  severity: ConcernSeverity.none,
  reason: '',
);

const flagged = SafetyAssessment(
  notifyStaff: true,
  category: ConcernCategory.scamOrMoney,
  severity: ConcernSeverity.high,
  reason: 'Asking for gift cards.',
  flaggedMessages: [1],
);

class FakeClassifier implements SafetyClassifier {
  FakeClassifier([this.result = safe]);
  SafetyAssessment result;
  Object? error;
  final List<ConversationSnapshot> seen = [];
  Completer<void>? gate;

  @override
  Future<SafetyAssessment> assess(ConversationSnapshot conversation) async {
    seen.add(conversation);
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    return result;
  }
}

class FakeNotifier implements StaffNotifier {
  final List<StaffAlert> alerts = [];
  @override
  Future<void> notify(StaffAlert alert) async => alerts.add(alert);
}

void main() {
  group('ConversationSnapshot', () {
    test('parses the page payload', () {
      final s = ConversationSnapshot.fromJson({
        'conversationId': 'thread:42',
        'title': 'Sam',
        'url': 'https://www.facebook.com/messages/t/42',
        'messages': [
          {'fromUser': false, 'sender': 'Sam', 'text': 'hi'},
          {'fromUser': true, 'sender': null, 'text': 'hello'},
        ],
      });
      expect(s.conversationId, 'thread:42');
      expect(s.messages.map((m) => m.text), ['hi', 'hello']);
      expect(s.messages.first.sender, 'Sam');
      expect(s.hasIncoming, isTrue);
    });

    test('rejects malformed payloads', () {
      expect(() => ConversationSnapshot.fromJson('nope'), throwsFormatException);
      expect(() => ConversationSnapshot.fromJson({'conversationId': 'x'}), throwsFormatException);
      expect(
        () => ConversationSnapshot.fromJson({
          'conversationId': 'x',
          'messages': [
            {'text': 'no author'}
          ],
        }),
        throwsFormatException,
      );
    });
  });

  group('MessageMonitor', () {
    late FakeClassifier classifier;
    late FakeNotifier notifier;
    late MessageMonitor monitor;

    setUp(() {
      classifier = FakeClassifier();
      notifier = FakeNotifier();
      monitor = MessageMonitor(
        classifier: classifier,
        notifier: notifier,
        cooldown: Duration.zero,
      );
    });
    tearDown(() => monitor.dispose());

    test('skips older messages the user scrolls back to', () async {
      final history = [for (var i = 0; i < 40; i++) (i.isEven, 'm$i')];
      await monitor.submit(snapshot(history.sublist(20)));
      expect(classifier.seen, hasLength(1));
      // Messenger only renders the rows on screen, so scrolling up sends
      // ever older windows; each overlaps what was already seen.
      for (var end = 35; end >= 10; end -= 5) {
        await monitor.submit(snapshot(history.sublist(end - 10, end)));
      }
      expect(classifier.seen, hasLength(1));
      // Back at the bottom, a new message is checked.
      await monitor.submit(snapshot([...history.sublist(21), (false, 'new')]));
      expect(classifier.seen, hasLength(2));
    });

    test('a repeated message after something new still counts as new', () async {
      await monitor.submit(snapshot([(false, 'ok'), (true, 'ok')]));
      await monitor.submit(snapshot([(false, 'ok'), (true, 'ok'), (false, 'send it'), (false, 'ok')]));
      expect(classifier.seen, hasLength(2));
    });

    test('sends only the last 20 messages', () async {
      await monitor.submit(snapshot([for (var i = 0; i < 30; i++) (i.isEven, 'm$i')]));
      expect(classifier.seen.single.messages, hasLength(20));
      expect(classifier.seen.single.messages.first.text, 'm10');
    });

    test('skips conversations with nothing from anyone else', () async {
      await monitor.submit(snapshot([(true, 'hello?')]));
      expect(classifier.seen, isEmpty);
    });

    test('does not check the same messages twice', () async {
      await monitor.submit(snapshot([(false, 'hi')]));
      await monitor.submit(snapshot([(false, 'hi')]));
      expect(classifier.seen, hasLength(1));
      await monitor.submit(snapshot([(false, 'hi'), (true, 'hey')]));
      expect(classifier.seen, hasLength(2));
    });

    test('notifies staff only when flagged', () async {
      await monitor.submit(snapshot([(false, 'hi')]));
      expect(notifier.alerts, isEmpty);

      classifier.result = flagged;
      await monitor.submit(snapshot([(false, 'hi'), (false, 'buy me gift cards')]));
      expect(notifier.alerts.single.flaggedMessages.single.text, 'buy me gift cards');
      expect(notifier.alerts.single.summary, contains('Asking for gift cards.'));
    });

    test('retries messages whose check failed', () async {
      classifier.error = Exception('offline');
      await monitor.submit(snapshot([(false, 'hi')]));
      classifier.error = null;
      await monitor.submit(snapshot([(false, 'hi')]));
      expect(classifier.seen, hasLength(2));
    });

    test('coalesces snapshots that arrive during a check', () async {
      classifier.gate = Completer<void>();
      final first = monitor.submit(snapshot([(false, 'a')]));
      await monitor.submit(snapshot([(false, 'a'), (false, 'b')]));
      await monitor.submit(snapshot([(false, 'a'), (false, 'b'), (false, 'c')]));
      classifier.gate!.complete();
      await first;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(classifier.seen.map((s) => s.messages.length), [1, 3]);
    });

    test('waits out the cooldown per conversation', () async {
      monitor = MessageMonitor(
        classifier: classifier,
        notifier: notifier,
        cooldown: const Duration(milliseconds: 100),
      );
      await monitor.submit(snapshot([(false, 'a')]));
      await monitor.submit(snapshot([(false, 'a'), (false, 'b')]));
      await monitor.submit(snapshot([(false, 'x')], id: 'thread:2'));
      expect(classifier.seen.map((s) => s.conversationId), ['thread:1', 'thread:2']);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(classifier.seen, hasLength(3));
      expect(classifier.seen.last.messages, hasLength(2));
    });
  });

  group('GeminiSafetyClassifier', () {
    String geminiReply(Map<String, Object?> answer, {String status = 'completed'}) => jsonEncode({
          'status': status,
          'object': 'interaction',
          'steps': [
            {'type': 'thought', 'signature': 'abc'},
            {
              'type': 'model_output',
              'content': [
                {'type': 'text', 'text': jsonEncode(answer)}
              ],
            },
          ],
        });

    test('sends the transcript and parses the answer', () async {
      late http.Request sent;
      final classifier = GeminiSafetyClassifier(
        apiKey: 'test-key',
        model: 'test-model',
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            geminiReply({
              'notifyStaff': true,
              'category': 'personalInfoRequest',
              'severity': 'medium',
              'reason': 'Asked for a login code.',
              'flaggedMessages': [0],
            }),
            200,
          );
        }),
      );

      final result = await classifier.assess(snapshot([(false, 'send me the code'), (true, 'ok')]));

      expect(sent.url.path, '/v1beta/interactions');
      expect(sent.headers['x-goog-api-key'], 'test-key');
      expect(sent.headers['Api-Revision'], GeminiSafetyClassifier.apiRevision);
      expect(sent.url.query, isNot(contains('test-key')));
      final body = jsonDecode(sent.body) as Map;
      expect(body['model'], 'test-model');
      expect(body['store'], isFalse);
      expect(body['system_instruction'], GeminiSafetyClassifier.systemPrompt);
      expect(body['input'], contains('"from": "other"'));
      expect(body['input'], contains('send me the code'));
      expect(body['response_format']['mime_type'], 'application/json');

      expect(result.notifyStaff, isTrue);
      expect(result.category, ConcernCategory.personalInfoRequest);
      expect(result.severity, ConcernSeverity.medium);
      expect(result.flaggedMessages, [0]);
    });

    test('ignores thought steps', () {
      final result = GeminiSafetyClassifier.parseResponse(geminiReply({
        'notifyStaff': false,
        'category': 'none',
        'severity': 'none',
        'reason': '',
        'flaggedMessages': [],
      }));
      expect(result.notifyStaff, isFalse);
    });

    final safeAnswer = {
      'notifyStaff': false,
      'category': 'none',
      'severity': 'none',
      'reason': '',
      'flaggedMessages': [],
    };
    String rateLimited(String model) => jsonEncode({
          'error': {
            'message': 'Rate limit exceeded for model $model (limit: 20 requests per day on '
                'Free Tier). Please retry in 2h20m2s or upgrade your tier.',
            'code': 'too_many_requests',
          }
        });

    test('falls back to the next model when rate limited, then skips the limited one', () async {
      final asked = <String>[];
      var now = DateTime(2026, 11, 8, 9);
      final classifier = GeminiSafetyClassifier(
        apiKey: 'k',
        model: 'main',
        fallbackModels: const ['backup-1', 'backup-2'],
        clock: () => now,
        client: MockClient((request) async {
          final model = (jsonDecode(request.body) as Map)['model'] as String;
          asked.add(model);
          if (model == 'main') return http.Response(rateLimited(model), 429);
          if (model == 'backup-1') return http.Response('{"error":{"message":"overloaded"}}', 503);
          return http.Response(geminiReply(safeAnswer), 200);
        }),
      );

      expect((await classifier.assess(snapshot([(false, 'hi')]))).notifyStaff, isFalse);
      expect(asked, ['main', 'backup-1', 'backup-2']);

      // Within the wait, the limited models aren't asked again.
      asked.clear();
      now = now.add(const Duration(seconds: 30));
      await classifier.assess(snapshot([(false, 'hi again')]));
      expect(asked, ['backup-2']);

      // backup-1's guessed one-minute wait is over; main's 2h20m isn't.
      asked.clear();
      now = now.add(const Duration(minutes: 2));
      await classifier.assess(snapshot([(false, 'and again')]));
      expect(asked, ['backup-1', 'backup-2']);
    });

    test('throws when every model is rate limited', () async {
      var requests = 0;
      final classifier = GeminiSafetyClassifier(
        apiKey: 'k',
        model: 'main',
        fallbackModels: const ['backup'],
        client: MockClient((request) async {
          requests++;
          return http.Response(rateLimited((jsonDecode(request.body) as Map)['model'] as String), 429);
        }),
      );
      await expectLater(
        classifier.assess(snapshot([(false, 'hi')])),
        throwsA(isA<SafetyClassifierException>()
            .having((e) => e.message, 'message', contains('rate limited'))),
      );
      expect(requests, 2);

      // While every model waits out its limit, nothing is sent.
      await expectLater(
        classifier.assess(snapshot([(false, 'hi again')])),
        throwsA(isA<SafetyClassifierException>()
            .having((e) => e.message, 'message', contains('not sending'))),
      );
      expect(requests, 2);
    });

    test('does not fall back on errors every model would hit', () async {
      var requests = 0;
      final classifier = GeminiSafetyClassifier(
        apiKey: 'k',
        client: MockClient((_) async {
          requests++;
          return http.Response('{"error":{"message":"API key not valid"}}', 400);
        }),
      );
      await expectLater(classifier.assess(snapshot([(false, 'hi')])),
          throwsA(isA<SafetyClassifierException>()));
      expect(requests, 1);
    });

    test('reads the retry delay from rate-limit messages', () {
      expect(GeminiSafetyClassifier.retryDelay('Please retry in 2h20m2s or upgrade'),
          const Duration(hours: 2, minutes: 20, seconds: 2));
      expect(GeminiSafetyClassifier.retryDelay('Please retry in 12.5s.'),
          const Duration(milliseconds: 12500));
      expect(GeminiSafetyClassifier.retryDelay('Resource exhausted'), isNull);
    });

    test('throws on HTTP errors, unfinished interactions and unreadable answers', () async {
      final failing = GeminiSafetyClassifier(
        apiKey: 'k',
        client: MockClient((_) async =>
            http.Response('{"error":{"message":"API key not valid"}}', 400)),
      );
      await expectLater(
        failing.assess(snapshot([(false, 'hi')])),
        throwsA(isA<SafetyClassifierException>()
            .having((e) => e.message, 'message', contains('API key not valid'))),
      );
      expect(
        () => GeminiSafetyClassifier.parseResponse(geminiReply({}, status: 'failed')),
        throwsA(isA<SafetyClassifierException>()),
      );
      expect(
        () => GeminiSafetyClassifier.parseResponse(geminiReply({'category': 'none'})),
        throwsA(isA<SafetyClassifierException>()),
      );
    });
  });
}
