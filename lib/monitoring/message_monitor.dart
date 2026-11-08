import 'dart:async';

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
/// - never the same set of messages twice;
/// - at most one request per conversation per [cooldown]. Snapshots that arrive
///   during it are coalesced, and only the latest is checked when it ends.
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

  static const int _maxRemembered = 1000;
  final Set<int> _checked = <int>{};
  final Map<String, _ConversationState> _conversations = {};

  /// Queues [snapshot] for checking. Returns once it has been checked, skipped,
  /// or folded into a later check.
  Future<void> submit(ConversationSnapshot snapshot) async {
    final window = snapshot.lastMessages(maxMessages);
    if (!window.hasIncoming || _checked.contains(window.fingerprint)) return;

    final state = _conversations.putIfAbsent(window.conversationId, _ConversationState.new);
    if (state.busy) {
      state.pending = window; // picked up when the running check finishes
      return;
    }
    final waited = state.lastRun == null ? null : DateTime.now().difference(state.lastRun!);
    if (waited != null && waited < cooldown) {
      state.pending = window;
      _schedulePending(state, cooldown - waited);
      return;
    }
    await _check(state, window);
  }

  void _schedulePending(_ConversationState state, Duration delay) {
    state.timer ??= Timer(delay, () {
      state.timer = null;
      final next = state.pending;
      state.pending = null;
      if (next != null) unawaited(submit(next));
    });
  }

  Future<void> _check(_ConversationState state, ConversationSnapshot window) async {
    state.busy = true;
    _remember(window.fingerprint);
    try {
      _log('${window.conversationId}: asking Gemini about ${window.messages.length} messages');
      final assessment = await classifier.assess(window);
      _log('${window.conversationId}: $assessment');
      if (assessment.notifyStaff) {
        await notifier.notify(StaffAlert(conversation: window, assessment: assessment));
      }
    } catch (e) {
      // Let a later snapshot of the same messages try again.
      _checked.remove(window.fingerprint);
      _log('${window.conversationId}: check failed: $e');
    } finally {
      state.busy = false;
      state.lastRun = DateTime.now();
      if (state.pending != null) _schedulePending(state, cooldown);
    }
  }

  void _remember(int fingerprint) {
    if (_checked.length >= _maxRemembered) _checked.remove(_checked.first);
    _checked.add(fingerprint);
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
  bool busy = false;
  DateTime? lastRun;
  ConversationSnapshot? pending;
  Timer? timer;
}
