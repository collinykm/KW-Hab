import 'conversation.dart';

/// Decides whether a conversation needs a support worker's attention.
/// [GeminiSafetyClassifier] is the real one; tests use fakes.
abstract class SafetyClassifier {
  Future<SafetyAssessment> assess(ConversationSnapshot conversation);
}

/// Kinds of concern the classifier can report. The [name]s are what Gemini is
/// asked to answer with.
enum ConcernCategory {
  none,
  scamOrMoney,
  personalInfoRequest,
  sexualContent,
  groomingOrManipulation,
  harassmentOrBullying,
  threatsOrViolence,
  selfHarmOrAbuse,
  suspiciousLink,
  other;

  static ConcernCategory parse(Object? value) =>
      values.firstWhere((c) => c.name == value, orElse: () => other);

  /// Plain words for alerts.
  String get label => switch (this) {
        none => 'No concern',
        scamOrMoney => 'Possible scam or money request',
        personalInfoRequest => 'Request for personal information',
        sexualContent => 'Sexual content',
        groomingOrManipulation => 'Grooming or manipulation',
        harassmentOrBullying => 'Harassment or bullying',
        threatsOrViolence => 'Threats or violence',
        selfHarmOrAbuse => 'Self-harm or abuse',
        suspiciousLink => 'Suspicious link',
        other => 'Other concern',
      };
}

enum ConcernSeverity {
  none,
  low,
  medium,
  high;

  static ConcernSeverity parse(Object? value) =>
      values.firstWhere((s) => s.name == value, orElse: () => medium);
}

class SafetyAssessment {
  const SafetyAssessment({
    required this.notifyStaff,
    required this.category,
    required this.severity,
    required this.reason,
    this.flaggedMessages = const [],
  });

  final bool notifyStaff;
  final ConcernCategory category;
  final ConcernSeverity severity;

  /// Plain-language explanation for the support worker.
  final String reason;

  /// Indexes into [ConversationSnapshot.messages] of the messages of concern.
  final List<int> flaggedMessages;

  @override
  String toString() =>
      'SafetyAssessment(notifyStaff: $notifyStaff, ${category.name}, ${severity.name}, $reason)';
}

class SafetyClassifierException implements Exception {
  SafetyClassifierException(this.message);
  final String message;

  @override
  String toString() => 'SafetyClassifierException: $message';
}
