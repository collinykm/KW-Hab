import 'package:flutter/foundation.dart';

import '../settings/app_settings.dart';
import '../settings/support_contact.dart';
import 'alert_channels.dart';
import 'safety_classifier.dart';
import 'staff_notifier.dart';

/// Sends alerts to the support people in [settings] by SMS or email, through
/// whichever [channels] are configured.
///
/// Each person is tried by their preferred method first. If that isn't set up
/// in `.env` or the send fails, their other details (if given) are used
/// instead, and the console says why.
///
/// The monitor re-checks a conversation whenever a new message arrives, so an
/// ongoing problem would be flagged again and again. Within [repeatAfter] of
/// an alert about a conversation, further alerts about it are only sent when
/// the severity goes up.
///
/// Never throws: a failed delivery is logged, and doesn't count as an alert,
/// so the next flagged check of that conversation tries again.
class DeliveringStaffNotifier implements StaffNotifier {
  DeliveringStaffNotifier({
    required this.settings,
    required List<AlertChannel> channels,
    this.repeatAfter = const Duration(minutes: 30),
    DateTime Function()? clock,
  })  : channels = {for (final c in channels) c.method: c},
        _clock = clock ?? DateTime.now;

  final AppSettings settings;
  final Map<ContactMethod, AlertChannel> channels;
  final Duration repeatAfter;
  final DateTime Function() _clock;

  final Map<String, ({DateTime at, ConcernSeverity severity})> _lastAlert = {};

  @override
  Future<void> notify(StaffAlert alert) async {
    final id = alert.conversation.conversationId;
    final severity = alert.assessment.severity;
    final now = _clock();
    final last = _lastAlert[id];
    if (last != null &&
        now.difference(last.at) < repeatAfter &&
        severity.index <= last.severity.index) {
      _log('$id: already alerted at ${last.at}, not repeating');
      return;
    }

    final contacts = settings.supportContacts.where((c) => c.methodsInOrder.isNotEmpty).toList();
    if (contacts.isEmpty) {
      _log('$id: STAFF ALERT not sent: no support people with a phone or email');
      return;
    }
    final results = await Future.wait([for (final c in contacts) _deliver(id, c, alert)]);
    if (results.contains(true)) {
      _lastAlert[id] = (at: now, severity: severity);
    }
  }

  /// Tries [contact]'s methods in order until one works.
  Future<bool> _deliver(String id, SupportContact contact, StaffAlert alert) async {
    final who = contact.name.isEmpty ? 'a support person' : contact.name;
    for (final method in contact.methodsInOrder) {
      final channel = channels[method];
      if (channel == null) {
        _log('$id: can\'t reach $who by ${_label(method)}: not set up in .env');
        continue;
      }
      try {
        final messageId = await channel.send(contact.addressFor(method), alert);
        _log('$id: alert sent to $who by ${_label(method)}'
            '${messageId == null ? '' : ' ($messageId)'}');
        return true;
      } catch (e) {
        _log('$id: alert to $who by ${_label(method)} failed: $e');
      }
    }
    _log('$id: STAFF ALERT not delivered to $who');
    return false;
  }

  static String _label(ContactMethod m) => m == ContactMethod.phone ? 'SMS' : 'email';

  // Logs names and methods only, never addresses or message text.
  static void _log(String message) => debugPrint('[kw-hab:message-monitor] $message');
}
