/// The last messages of one Messenger conversation, as read from the page by
/// `assets/injections/js/message-monitor.js`.
class ConversationSnapshot {
  const ConversationSnapshot({
    required this.conversationId,
    required this.title,
    required this.messages,
    this.url,
  });

  /// `thread:<id>` for full-page Messenger, `popup:<name>` for chat popups.
  final String conversationId;

  /// Who the conversation is with, as Facebook labels it.
  final String title;
  final String? url;

  /// Oldest first.
  final List<MonitoredMessage> messages;

  /// Parses the page's payload. Throws [FormatException] on anything unexpected,
  /// since the page (and Facebook's scripts in it) can send whatever they like.
  factory ConversationSnapshot.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('snapshot is not an object');
    final id = json['conversationId'];
    final messages = json['messages'];
    if (id is! String || id.isEmpty) throw const FormatException('missing conversationId');
    if (messages is! List) throw const FormatException('missing messages');
    return ConversationSnapshot(
      conversationId: id,
      title: json['title'] is String ? json['title'] as String : '',
      url: json['url'] is String ? json['url'] as String : null,
      messages: [for (final m in messages) MonitoredMessage.fromJson(m)],
    );
  }

  bool get hasIncoming => messages.any((m) => !m.fromUser);

  /// The same conversation cut down to its last [count] messages.
  ConversationSnapshot lastMessages(int count) => messages.length <= count
      ? this
      : ConversationSnapshot(
          conversationId: conversationId,
          title: title,
          url: url,
          messages: messages.sublist(messages.length - count),
        );

  /// Identifies this exact set of messages, so the same window isn't sent to
  /// Gemini twice.
  int get fingerprint => Object.hash(
        conversationId,
        Object.hashAll(messages.map((m) => Object.hash(m.fromUser, m.text))),
      );
}

class MonitoredMessage {
  const MonitoredMessage({required this.fromUser, required this.text, this.sender});

  /// True when the app's user sent it, false when someone else did.
  final bool fromUser;

  /// The other person's name when the page could tell (group chats).
  final String? sender;
  final String text;

  factory MonitoredMessage.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('message is not an object');
    final fromUser = json['fromUser'];
    final text = json['text'];
    if (fromUser is! bool || text is! String) {
      throw const FormatException('message needs fromUser and text');
    }
    final sender = json['sender'];
    return MonitoredMessage(
      fromUser: fromUser,
      text: text,
      sender: sender is String && sender.isNotEmpty ? sender : null,
    );
  }
}
