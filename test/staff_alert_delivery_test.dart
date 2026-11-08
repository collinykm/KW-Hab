import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kw_hab/monitoring/alert_channels.dart';
import 'package:kw_hab/monitoring/conversation.dart';
import 'package:kw_hab/monitoring/delivering_staff_notifier.dart';
import 'package:kw_hab/monitoring/monitoring_setup.dart';
import 'package:kw_hab/monitoring/safety_classifier.dart';
import 'package:kw_hab/monitoring/staff_notifier.dart';
import 'package:kw_hab/settings/app_settings.dart';
import 'package:kw_hab/settings/settings_storage.dart';
import 'package:kw_hab/settings/support_contact.dart';

StaffAlert alertFor({
  String id = 'thread:1',
  ConcernSeverity severity = ConcernSeverity.high,
  List<String> texts = const ['hi', 'send me gift cards'],
}) =>
    StaffAlert(
      conversation: ConversationSnapshot(
        conversationId: id,
        title: 'Sam',
        messages: [for (final t in texts) MonitoredMessage(fromUser: false, text: t, sender: 'Sam')],
      ),
      assessment: SafetyAssessment(
        notifyStaff: true,
        category: ConcernCategory.scamOrMoney,
        severity: severity,
        reason: 'Asking for gift cards.',
        flaggedMessages: [texts.length - 1],
      ),
    );

class FakeChannel implements AlertChannel {
  FakeChannel(this.method);
  @override
  final ContactMethod method;
  final List<String> sentTo = [];
  bool fail = false;

  @override
  Future<String?> send(String address, StaffAlert alert) async {
    if (fail) throw AlertDeliveryException('nope');
    sentTo.add(address);
    return null;
  }
}

const ana = SupportContact(id: 'a', name: 'Ana', phone: '519-555-0101', email: 'ana@example.org',
    preferredMethod: ContactMethod.phone);
const bo = SupportContact(id: 'b', name: 'Bo', email: 'bo@example.org', preferredMethod: ContactMethod.email);

void main() {
  group('StaffAlert', () {
    test('uses plain-language labels', () {
      final a = alertFor();
      expect(a.emailSubject, 'KW Hab safety alert: Possible scam or money request (high priority)');
      expect(a.summary, contains('- Sam: send me gift cards'));
      expect(a.summary, isNot(contains('- Sam: hi')));
    });

    test('smsBody fits in one Twilio message', () {
      final long = 'x' * 1000;
      final a = StaffAlert(
        conversation: ConversationSnapshot(
          conversationId: 't',
          title: 'Sam',
          messages: [for (var i = 0; i < 20; i++) MonitoredMessage(fromUser: false, text: long)],
        ),
        assessment: const SafetyAssessment(
          notifyStaff: true,
          category: ConcernCategory.other,
          severity: ConcernSeverity.low,
          reason: 'Odd.',
        ),
      );
      expect(a.smsBody.length, lessThanOrEqualTo(1600));
      expect(a.smsBody, contains('Odd.'));
      expect(a.smsBody, contains('…'));
    });
  });

  test('methodsInOrder: preferred first, then any other details given', () {
    expect(ana.methodsInOrder, [ContactMethod.phone, ContactMethod.email]);
    expect(bo.methodsInOrder, [ContactMethod.email]);
    expect(const SupportContact(id: 'c', phone: '1', email: 'c@x', preferredMethod: ContactMethod.email)
        .methodsInOrder, [ContactMethod.email, ContactMethod.phone]);
  });

  test('alertRecipients falls back to a method the app can send by', () {
    final r = alertRecipients([ana, bo], available: [ContactMethod.email]);
    expect(r.map((x) => (x.contact.name, x.method, x.address)), [
      ('Ana', ContactMethod.email, 'ana@example.org'),
      ('Bo', ContactMethod.email, 'bo@example.org'),
    ]);
  });

  test('normalizePhoneNumber', () {
    expect(normalizePhoneNumber('(519) 555-0101'), '+15195550101');
    expect(normalizePhoneNumber('1 519 555 0101'), '+15195550101');
    expect(normalizePhoneNumber('+44 20 7946 0958'), '+442079460958');
    expect(normalizePhoneNumber('555-0101'), isNull);
    expect(normalizePhoneNumber(''), isNull);
  });

  group('DeliveringStaffNotifier', () {
    late AppSettings settings;
    late FakeChannel sms;
    late FakeChannel email;
    late DateTime now;
    late DeliveringStaffNotifier notifier;

    setUp(() {
      settings = AppSettings(storage: MemorySettingsStorage())..supportContacts = [ana, bo];
      sms = FakeChannel(ContactMethod.phone);
      email = FakeChannel(ContactMethod.email);
      now = DateTime(2026, 11, 8, 12);
      notifier = DeliveringStaffNotifier(settings: settings, channels: [sms, email], clock: () => now);
    });

    test('sends each person their preferred method', () async {
      await notifier.notify(alertFor());
      expect(sms.sentTo, ['519-555-0101']);
      expect(email.sentTo, ['bo@example.org']);
    });

    test('falls back to the other method when the preferred one is not set up', () async {
      notifier = DeliveringStaffNotifier(settings: settings, channels: [email], clock: () => now);
      await notifier.notify(alertFor());
      expect(email.sentTo, ['ana@example.org', 'bo@example.org']);
    });

    test('falls back to the other method when the preferred one fails', () async {
      sms.fail = true;
      await notifier.notify(alertFor());
      expect(email.sentTo, unorderedEquals(['ana@example.org', 'bo@example.org']));
    });

    test('does not repeat an alert unless it gets worse or time passes', () async {
      await notifier.notify(alertFor(severity: ConcernSeverity.medium));
      await notifier.notify(alertFor(severity: ConcernSeverity.medium));
      await notifier.notify(alertFor(severity: ConcernSeverity.low));
      expect(sms.sentTo, hasLength(1));

      await notifier.notify(alertFor(severity: ConcernSeverity.high));
      expect(sms.sentTo, hasLength(2));

      await notifier.notify(alertFor(id: 'thread:2'));
      expect(sms.sentTo, hasLength(3));

      now = now.add(const Duration(minutes: 31));
      await notifier.notify(alertFor(severity: ConcernSeverity.high));
      expect(sms.sentTo, hasLength(4));
    });

    test('a failed delivery does not throw, and is retried next time', () async {
      sms.fail = true;
      email.fail = true;
      await notifier.notify(alertFor());
      sms.fail = false;
      email.fail = false;
      await notifier.notify(alertFor());
      expect(sms.sentTo, hasLength(1));
    });
  });

  group('TwilioSmsChannel', () {
    test('posts a form to the Messages API', () async {
      late http.Request sent;
      final channel = TwilioSmsChannel(
        accountSid: 'AC123',
        authToken: 'tok',
        from: '+15195550000',
        client: MockClient((r) async {
          sent = r;
          return http.Response('{"sid":"SM1"}', 201);
        }),
      );
      expect(await channel.send('519 555 0101', alertFor()), 'SM1');
      expect(sent.url.toString(), 'https://api.twilio.com/2010-04-01/Accounts/AC123/Messages.json');
      expect(sent.headers['Authorization'], 'Basic ${base64Encode(utf8.encode('AC123:tok'))}');
      expect(sent.bodyFields['To'], '+15195550101');
      expect(sent.bodyFields['From'], '+15195550000');
      expect(sent.bodyFields['Body'], contains('Asking for gift cards.'));
    });

    test('signs in with an API key when given one', () async {
      late http.Request sent;
      final channel = TwilioSmsChannel(
        accountSid: 'AC123',
        apiKeySid: 'SK456',
        apiKeySecret: 'secret',
        from: '+15195550000',
        client: MockClient((r) async {
          sent = r;
          return http.Response('{"sid":"SM1"}', 201);
        }),
      );
      await channel.send('5195550101', alertFor());
      expect(sent.url.path, '/2010-04-01/Accounts/AC123/Messages.json');
      expect(sent.headers['Authorization'], 'Basic ${base64Encode(utf8.encode('SK456:secret'))}');
    });

    test('config problems are spelled out', () {
      String? check({
        String sid = 'AC1',
        String token = 't',
        String keySid = '',
        String keySecret = '',
        String from = '+15195550000',
      }) =>
          twilioConfigProblem(
              accountSid: sid, authToken: token, apiKeySid: keySid, apiKeySecret: keySecret, from: from);

      expect(check(), isNull);
      expect(check(token: '', keySid: 'SK1', keySecret: 's'), isNull);
      expect(check(from: 'MG1'), isNull);
      expect(check(sid: '', token: '', from: ''), '');
      expect(check(sid: 'SK1'), contains('TWILIO_API_KEY_SID'));
      expect(check(from: '2B17372508034'), contains('+15195550123'));
      expect(check(from: ''), contains('TWILIO_FROM is missing'));
      expect(check(token: ''), contains('TWILIO_AUTH_TOKEN'));
      expect(check(token: '', keySid: 'SK1'), contains('TWILIO_API_KEY_SECRET is missing'));
    });

    test('uses a Messaging Service SID, and reports errors', () async {
      late http.Request sent;
      final channel = TwilioSmsChannel(
        accountSid: 'AC123',
        authToken: 'tok',
        from: 'MG999',
        client: MockClient((r) async {
          sent = r;
          return http.Response('{"code":21608,"message":"The number is unverified."}', 400);
        }),
      );
      await expectLater(
        channel.send('5195550101', alertFor()),
        throwsA(isA<AlertDeliveryException>()
            .having((e) => e.message, 'message', contains('The number is unverified.'))),
      );
      expect(sent.bodyFields['MessagingServiceSid'], 'MG999');
      expect(sent.bodyFields.containsKey('From'), isFalse);
      await expectLater(channel.send('call me', alertFor()), throwsA(isA<AlertDeliveryException>()));
    });
  });

  group('ResendEmailChannel', () {
    test('posts the email as JSON', () async {
      late http.Request sent;
      final channel = ResendEmailChannel(
        apiKey: 're_test',
        from: 'KW Hab <alerts@example.org>',
        client: MockClient((r) async {
          sent = r;
          return http.Response('{"id":"e1"}', 200);
        }),
      );
      expect(await channel.send(' bo@example.org ', alertFor()), 'e1');
      expect(sent.url, ResendEmailChannel.endpoint);
      expect(sent.headers['Authorization'], 'Bearer re_test');
      final body = jsonDecode(sent.body) as Map;
      expect(body['from'], 'KW Hab <alerts@example.org>');
      expect(body['to'], ['bo@example.org']);
      expect(body['subject'], contains('Possible scam'));
      expect(body['text'], contains('Asking for gift cards.'));
    });

    test('reports errors', () async {
      final channel = ResendEmailChannel(
        apiKey: 'bad',
        from: ResendEmailChannel.defaultFrom,
        client: MockClient((_) async =>
            http.Response('{"statusCode":401,"name":"validation_error","message":"API key is invalid"}', 401)),
      );
      await expectLater(
        channel.send('bo@example.org', alertFor()),
        throwsA(isA<AlertDeliveryException>()
            .having((e) => e.message, 'message', contains('API key is invalid'))),
      );
    });
  });
}
