import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Work around Messenger's shared worker remaining startup-paused in WebView2.
/// Reproduced on 157.0.4341.42: ordinary expressions work, but timers do not;
/// Runtime.runIfWaitingForDebugger restores message loading without a PIN reset.
/// The target's waitingForDebugger flag can be false in this state.
/// Uses WebView2's internal protocol API; no remote debugging port is needed.
class WindowsMessengerWorker {
  static final _running = Expando<Future<void>>();
  static const _replyEvent = 'Target.receivedMessageFromTarget';
  static const _timeout = Duration(seconds: 3);

  static Future<void> resume(InAppWebViewController controller) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return;
    final pending = _running[controller];
    if (pending != null) return pending;
    final operation = _resume(controller);
    _running[controller] = operation;
    try {
      await operation;
    } finally {
      _running[controller] = null;
    }
  }

  static Future<void> _resume(InAppWebViewController controller) async {
    Future<dynamic> call(String method, [Map<String, dynamic>? parameters]) =>
        controller
            .callDevToolsProtocolMethod(
              methodName: method,
              parameters: parameters,
            )
            .timeout(_timeout);

    String? session;
    var listening = false;
    try {
      final targets = await call('Target.getTargets');
      for (final target in targets['targetInfos'] as List) {
        final uri = Uri.tryParse(target['url'] as String? ?? '');
        if (target['type'] != 'shared_worker' ||
            target['title'] != 'MAWMainV4WebWorkerBundle' ||
            uri?.scheme != 'https' ||
            uri?.host != 'www.facebook.com') {
          continue;
        }
        final attached = await call('Target.attachToTarget', {
          'targetId': target['targetId'],
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
        break;
      }
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
