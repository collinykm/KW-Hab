import 'package:flutter/foundation.dart';

import '../settings/app_settings.dart';
import '../settings/support_contact.dart';
import 'conversation.dart';
import 'safety_classifier.dart';

/// What a support worker is told when a conversation is flagged.
class StaffAlert {
  StaffAlert({required this.conversation, required this.assessment, DateTime? at})
      : at = at ?? DateTime.now();

  final ConversationSnapshot conversation;
  final SafetyAssessment assessment;
  final DateTime at;

  /// The messages Gemini pointed at (all of them if it pointed at none).
  List<MonitoredMessage> get flaggedMessages {
    final picked = [
      for (final i in assessment.flaggedMessages)
        if (i >= 0 && i < conversation.messages.length) conversation.messages[i]
    ];
    return picked.isEmpty ? conversation.messages : picked;
  }

  /// Plain-text summary: the email body, and the console placeholder.
  String get summary => _body();

  /// [summary] kept within Twilio's 1600-character limit: each message is cut
  /// to [maxMessageLength], and messages are dropped from the end if needed.
  String get smsBody {
    const limit = 1600;
    var messages = flaggedMessages;
    while (true) {
      final body = _body(messages: messages, maxMessageLength: 200);
      if (body.length <= limit) return body;
      if (messages.isEmpty) return '${body.substring(0, limit - 1)}…';
      messages = messages.sublist(0, messages.length - 1);
    }
  }

  String get emailSubject => 'KW Hab safety alert: ${assessment.category.label} '
      '(${assessment.severity.name} priority)';

  String _body({List<MonitoredMessage>? messages, int? maxMessageLength}) {
    final buffer = StringBuffer()
      ..writeln('KW Hab safety alert: ${assessment.category.label} '
          '(${assessment.severity.name} priority)')
      ..writeln('Conversation with: ${conversation.title}')
      ..writeln(assessment.reason);
    for (final m in messages ?? flaggedMessages) {
      final who = m.fromUser ? 'User' : (m.sender ?? 'Other person');
      var text = m.text;
      if (maxMessageLength != null && text.length > maxMessageLength) {
        text = '${text.substring(0, maxMessageLength - 1)}…';
      }
      buffer.writeln('- $who: $text');
    }
    return buffer.toString().trimRight();
  }
}

/// One delivery of an alert: a support person and the way to reach them.
typedef AlertRecipient = ({SupportContact contact, ContactMethod method, String address});

/// Who an alert goes to: every reachable support person, once each, by their
/// preferred method (or whatever details they gave, if that one is blank).
/// [available] limits it to the methods the app can send by; someone whose
/// preferred method isn't available gets the other one if they gave it.
List<AlertRecipient> alertRecipients(
  Iterable<SupportContact> contacts, {
  Iterable<ContactMethod> available = ContactMethod.values,
}) =>
    [
      for (final c in contacts)
        if (c.reachableBy(available) case final m?)
          (contact: c, method: m, address: c.addressFor(m)),
    ];

/// Delivers a [StaffAlert] to the user's support people.
///
/// `DeliveringStaffNotifier` (SMS/email) is the real one, chosen in
/// `lib/monitoring/monitoring_setup.dart`; [ConsoleStaffNotifier] is used when
/// no SMS or email keys are set.
abstract class StaffNotifier {
  Future<void> notify(StaffAlert alert);
}

/// Placeholder: prints the alert, and who it would go to, to the console
/// (`flutter run` output).
class ConsoleStaffNotifier implements StaffNotifier {
  ConsoleStaffNotifier([this.settings]);

  final AppSettings? settings;

  @override
  Future<void> notify(StaffAlert alert) async {
    final recipients = alertRecipients(settings?.supportContacts ?? const []);
    final to = recipients.isEmpty
        ? '(no support people set up in onboarding)'
        : recipients.map((r) => '${r.contact.name} by ${r.method.name} (${r.address})').join(', ');
    debugPrint('[kw-hab:message-monitor] STAFF ALERT to $to\n${alert.summary}');
  }
}
