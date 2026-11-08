import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Work around Messenger's shared worker remaining startup-paused in WebView2.
/// Reproduced on 157.0.4341.42: ordinary expressions work, but timers do not;
/// Runtime.runIfWaitingForDebugger restores message loading without a PIN reset.
/// The target's waitingForDebugger flag can be false in this state.
/// Uses WebView2's internal protocol API; no remote debugging port is needed.
///
/// The worker can start after the page has loaded (opening Messages from the
/// top bar is an in-page navigation), so [watch] also resumes each Messenger
/// worker as it appears, not only at [resume] calls on page load.
class WindowsMessengerWorker {
  static final _running = Expando<Future<void>>();
  static final _runAgain = Expando<bool>();
  static final _watching = Expando<bool>();
  static const _replyEvent = 'Target.receivedMessageFromTarget';
  static const _createdEvent = 'Target.targetCreated';
  static const _timeout = Duration(seconds: 3);

  /// A resume sent before the worker has reached its startup pause is
  /// acknowledged but does nothing, and nothing tells us when it gets there.
  /// So each resume is repeated a few times; it's harmless on a running worker.
  static const _followUps = [
    Duration(seconds: 1),
    Duration(seconds: 3),
    Duration(seconds: 6),
    Duration(seconds: 12),
  ];
  static final _followUpTimers = Expando<List<Timer>>();

  static bool get _isWindows => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  static bool _isMessengerWorker(Map target) {
    final uri = Uri.tryParse(target['url'] as String? ?? '');
    return target['type'] == 'shared_worker' &&
        target['title'] == 'MAWMainV4WebWorkerBundle' &&
        uri?.scheme == 'https' &&
        uri?.host == 'www.facebook.com';
  }

  /// Call once when the web view is created: resumes every Messenger worker
  /// that starts from then on.
  static Future<void> watch(InAppWebViewController controller) async {
    if (!_isWindows || _watching[controller] == true) return;
    _watching[controller] = true;
    try {
      await controller.addDevToolsProtocolEventListener(
        eventName: _createdEvent,
        callback: (data) {
          final target = data is Map ? data['targetInfo'] : null;
          if (target is Map && _isMessengerWorker(target)) {
            unawaited(resume(controller));
          }
        },
      );
      await controller.callDevToolsProtocolMethod(
        methodName: 'Target.setDiscoverTargets',
        parameters: {'discover': true},
      );
    } catch (error) {
      _watching[controller] = false;
      debugPrint('[kw-hab:worker] Could not watch for Messenger: $error');
    }
  }

  /// Resumes now, and again a few times over the next seconds.
  static Future<void> resume(InAppWebViewController controller) {
    if (!_isWindows) return Future.value();
    _followUpTimers[controller]?.forEach((timer) => timer.cancel());
    _followUpTimers[controller] = [
      for (final delay in _followUps)
        Timer(delay, () => unawaited(_resumeOnce(controller))),
    ];
    return _resumeOnce(controller);
  }

  static Future<void> _resumeOnce(InAppWebViewController controller) async {
    final pending = _running[controller];
    if (pending != null) {
      // A worker may have started after this run listed the targets.
      _runAgain[controller] = true;
      return pending;
    }
    final operation = _resumeUntilSettled(controller);
    _running[controller] = operation;
    try {
      await operation;
    } finally {
      _running[controller] = null;
    }
  }

  static Future<void> _resumeUntilSettled(InAppWebViewController controller) async {
    do {
      _runAgain[controller] = false;
      await _resume(controller);
    } while (_runAgain[controller] == true);
  }

  static Future<void> _resume(InAppWebViewController controller) async {
    Future<dynamic> call(String method, [Map<String, dynamic>? parameters]) =>
        controller
            .callDevToolsProtocolMethod(
              methodName: method,
              parameters: parameters,
            )
            .timeout(_timeout);

    try {
      final targets = await call('Target.getTargets');
      // Every match: an old worker can still be listed next to a new one.
      for (final target in targets['targetInfos'] as List) {
        if (target is Map && _isMessengerWorker(target)) {
          await _resumeTarget(controller, call, target['targetId'] as String);
        }
      }
    } catch (error) {
      debugPrint('[kw-hab:worker] Could not resume Messenger: $error');
    }
  }

  static Future<void> _resumeTarget(
    InAppWebViewController controller,
    Future<dynamic> Function(String, [Map<String, dynamic>?]) call,
    String targetId,
  ) async {
    String? session;
    var listening = false;
    try {
      final attached = await call('Target.attachToTarget', {
        'targetId': targetId,
        'flatten': false,
      });
      session = attached['sessionId'] as String;
      final reply = Completer<void>();
      await controller.addDevToolsProtocolEventListener(
        eventName: _replyEvent,
        callback: (data) {
          if (data is! Map || data['sessionId'] != session) return;
          final message = jsonDecode(data['message'] as String) as Map;
          if (message['id'] != 1 || reply.isCompleted) return;
          if (message['error'] != null) {
            reply.completeError(StateError('Worker resume was rejected'));
          } else {
            reply.complete();
          }
        },
      );
      listening = true;
      // Install the error handler before a protocol response can arrive.
      final confirmed = reply.future.timeout(_timeout);
      await Future.wait([
        confirmed,
        call('Target.sendMessageToTarget', {
          'sessionId': session,
          'message': jsonEncode({
            'id': 1,
            'method': 'Runtime.runIfWaitingForDebugger',
          }),
        }),
      ]);
      debugPrint('[kw-hab:worker] Messenger startup resume acknowledged');
    } catch (error) {
      debugPrint('[kw-hab:worker] Could not resume Messenger: $error');
    } finally {
      if (listening) {
        try {
          await controller.removeDevToolsProtocolEventListener(
            eventName: _replyEvent,
          );
        } catch (_) {
          /* The web view may have closed during navigation. */
        }
      }
      if (session != null) {
        try {
          await call('Target.detachFromTarget', {'sessionId': session});
        } catch (_) {
          /* The worker may have exited during navigation. */
        }
      }
    }
  }
}
