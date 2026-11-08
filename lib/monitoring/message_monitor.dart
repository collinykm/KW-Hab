import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'conversation.dart';
import 'safety_classifier.dart';
import 'staff_notifier.dart';

/// Takes conversation snapshots from the page, sends the last [maxMessages]
/// of each new one to the [classifier], and tells the [notifier] when staff
/// should know.
///
/// Limits on what reaches Gemini:
/// - only conversations with at least one message from someone else;
/// - only when there's a new message at the bottom. The page sends a snapshot
///   whenever the visible messages change, which includes scrolling back
///   through older ones (Messenger only renders the rows on screen) and
///   re-renders; those are skipped;
/// - at most one request per conversation per [cooldown]. Snapshots that arrive
///   in the meantime are coalesced, and only the latest is checked.
class MessageMonitor {
  MessageMonitor({
    required this.classifier,
    required this.notifier,
    this.maxMessages = 20,
    this.cooldown = const Duration(seconds: 20),
  });

  final SafetyClassifier classifier;
  final StaffNotifier notifier;
  final int maxMessages;
  final Duration cooldown;

  final Map<String, _ConversationState> _conversations = {};

  /// Queues [snapshot] for checking. Returns once it has been checked, skipped,
  /// or queued for a later check.
  Future<void> submit(ConversationSnapshot snapshot) {
    final window = snapshot.lastMessages(maxMessages);
    if (!window.hasIncoming) return Future.value();
    final state = _conversations.putIfAbsent(window.conversationId, _ConversationState.new);
    return _consider(state, window);
  }

  Future<void> _consider(_ConversationState state, ConversationSnapshot window) async {
    final keys = _messageKeys(window);
    final lastSeen = keys.lastIndexWhere(state.seen.contains);
    if (lastSeen == keys.length - 1) {
      // The same messages again, or older ones the user scrolled back to.
      state.see(keys);
      _log('${window.conversationId}: nothing new at the bottom, not asking Gemini');
      return;
    }
    if (state.busy) {
      state.pending = window; // reconsidered when the running check finishes
      return;
    }

    if (state.lastRun case final lastRun?) {
      final rest = cooldown - DateTime.now().difference(lastRun);
      if (rest > Duration.zero) {
        _queue(state, window, rest);
        return;
      }
    }
    await _check(state, window, keys);
  }

  /// Checks the latest pending window once [delay] (the rest of the
  /// cooldown) is up.
  void _queue(_ConversationState state, ConversationSnapshot window, Duration delay) {
    state.pending = window;
    state.timer ??= Timer(delay, () {
      state.timer = null;
      final next = state.pending;
      state.pending = null;
      if (next != null) unawaited(_consider(state, next));
    });
  }

  Future<void> _check(
    _ConversationState state,
    ConversationSnapshot window,
    List<int> keys,
  ) async {
    // This is the newest window, so it covers anything queued.
    state.timer?.cancel();
    state.timer = null;
    state.pending = null;
    state.busy = true;
    final added = state.see(keys);
    try {
      _log('${window.conversationId}: asking Gemini about ${window.messages.length} messages');
      final assessment = await classifier.assess(window);
      _log('${window.conversationId}: $assessment');
      if (assessment.notifyStaff) {
        await notifier.notify(StaffAlert(conversation: window, assessment: assessment));
      }
    } catch (e) {
      // Let a later snapshot of the same messages try again.
      state.seen.removeAll(added);
      _log('${window.conversationId}: check failed: $e');
    } finally {
      state.busy = false;
      state.lastRun = DateTime.now();
      final next = state.pending;
      state.pending = null;
      if (next != null) unawaited(_consider(state, next));
    }
  }

  /// Identifies each message by its content and the message before it, so a
  /// repeated "ok" after something new still counts as new.
  static List<int> _messageKeys(ConversationSnapshot window) {
    int content(MonitoredMessage m) => Object.hash(m.fromUser, m.sender, m.text);
    final messages = window.messages;
    return [
      for (var i = 0; i < messages.length; i++)
        Object.hash(content(messages[i]), i == 0 ? null : content(messages[i - 1])),
    ];
  }

  /// Cancels pending checks.
  void dispose() {
    for (final state in _conversations.values) {
      state.timer?.cancel();
    }
    _conversations.clear();
  }

  // Logs ids and verdicts only, never message text.
  static void _log(String message) => debugPrint('[kw-hab:message-monitor] $message');
}

class _ConversationState {
  static const int _maxSeen = 500;

  bool busy = false;
  DateTime? lastRun;
  ConversationSnapshot? pending;
  Timer? timer;

  /// Keys of messages already checked (or scrolled past), oldest first.
  final LinkedHashSet<int> seen = LinkedHashSet<int>();

  /// Marks [keys] seen and returns the ones that weren't.
  List<int> see(List<int> keys) {
    final added = [for (final k in keys) if (seen.add(k)) k];
    while (seen.length > _maxSeen) {
      seen.remove(seen.first);
    }
    return added;
  }
}
