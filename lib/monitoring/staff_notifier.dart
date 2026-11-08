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

  /// Plain-text summary, suitable for an SMS or email body.
  String get summary {
    final buffer = StringBuffer()
      ..writeln('KW Hab safety alert (${assessment.severity.name}, ${assessment.category.name})')
      ..writeln('Conversation with: ${conversation.title}')
      ..writeln(assessment.reason);
    for (final m in flaggedMessages) {
      final who = m.fromUser ? 'User' : (m.sender ?? 'Other person');
      buffer.writeln('- $who: ${m.text}');
    }
    return buffer.toString().trimRight();
  }
}

/// One delivery of an alert: a support person and the way to reach them.
typedef AlertRecipient = ({SupportContact contact, ContactMethod method, String address});

/// Who an alert goes to: every reachable support person, once each, by their
/// preferred method (or whatever details they gave, if that one is blank).
List<AlertRecipient> alertRecipients(Iterable<SupportContact> contacts) => [
      for (final c in contacts)
        if (c.contactMethod case final m?) (contact: c, method: m, address: c.addressFor(m)),
    ];

/// Delivers a [StaffAlert] to the user's support people.
///
/// The real delivery (SMS or email, to the support people entered during
/// onboarding; see [alertRecipients]) doesn't exist yet. Implement this
/// interface for it and swap it in where the monitor is built
/// (`lib/monitoring/monitoring_setup.dart`).
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
