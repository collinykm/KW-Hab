import 'package:flutter/foundation.dart';

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

/// Delivers a [StaffAlert] to the user's support worker.
///
/// The real delivery (SMS or email, to a contact the support worker enters
/// during onboarding) doesn't exist yet. Implement this interface for it and
/// swap it in where the monitor is built (`lib/monitoring/monitoring_setup.dart`).
abstract class StaffNotifier {
  Future<void> notify(StaffAlert alert);
}

/// Placeholder: prints the alert to the console (`flutter run` output).
class ConsoleStaffNotifier implements StaffNotifier {
  @override
  Future<void> notify(StaffAlert alert) async {
    debugPrint('[kw-hab:message-monitor] STAFF ALERT\n${alert.summary}');
  }
}
