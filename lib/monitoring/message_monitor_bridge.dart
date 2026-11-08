import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../shell/page_bridge.dart';
import '../shell/url_routing.dart';
import 'conversation.dart';
import 'message_monitor.dart';

/// Receives conversation snapshots from `assets/injections/js/message-monitor.js`.
class MessageMonitorBridge implements PageBridge {
  MessageMonitorBridge(this.monitor);

  /// Must match `HANDLER` in message-monitor.js.
  static const String handlerName = 'kwMessageMonitor';

  final MessageMonitor monitor;

  @override
  void attach(InAppWebViewController controller) {
    controller.addJavaScriptHandler(
      handlerName: handlerName,
      callback: (JavaScriptHandlerFunctionData data) {
        // Only Facebook's own top-level page, not embedded third-party frames.
        if (!data.isMainFrame || !isInAppHost(data.origin.host)) {
          debugPrint('[kw-hab:message-monitor] ignored call from ${data.origin} '
              '(main frame: ${data.isMainFrame})');
          return null;
        }
        if (data.args.isEmpty) return null;
        try {
          final snapshot = ConversationSnapshot.fromJson(data.args.first);
          debugPrint('[kw-hab:message-monitor] received ${snapshot.messages.length} '
              'messages from ${snapshot.conversationId}');
          unawaited(monitor.submit(snapshot));
        } on FormatException catch (e) {
          debugPrint('[kw-hab:message-monitor] ignored bad snapshot: ${e.message}');
        }
        return null;
      },
    );
  }
}
