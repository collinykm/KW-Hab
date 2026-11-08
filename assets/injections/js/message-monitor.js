// Message monitoring. Reads the last messages of the open Messenger
// conversation (both sides) and hands them to the Dart side, which asks Gemini
// whether support staff should be told. Nothing here talks to Gemini or holds
// a key: Facebook's scripts can read everything in this page. See
// lib/monitoring/ for the Dart side.
//
// What gets sent: { conversationId, title, url, messages: [{ fromUser, sender,
// text }] }, oldest first, at most MAX_MESSAGES, and only when the
// conversation has at least one message from someone else and its tail
// changed since the last send.
//
// Facebook's DOM is the fragile part. All of the selectors and guesses live in
// the "Reading the DOM" section. To check what is extracted, open the Web
// Inspector on a conversation and run `kwHabMessageMonitorPreview()`.

var MAX_MESSAGES = 20;
var MAX_TEXT = 2000;
var SETTLE_MS = 1500;
var HANDLER = 'kwMessageMonitor';

// ---- Reading the DOM -------------------------------------------------------

// The scrollable list of messages, both on /messages/t/… and in chat popups.
var CONVERSATION = '[aria-label^="Messages in conversation"]';
var CONVERSATION_PREFIX = /^Messages in conversation\s*(with|titled|called)?\s*/i;
// One message per row. Messenger (incl. end-to-end encrypted chats, Nov 2026)
// wraps each in a [data-virtualized] div around a role="article"; older
// layouts used role="row".
var ROW = '[data-virtualized], [role="row"]';
var MESSAGE = '[role="article"]';
var HEADING = 'h1, h2, h3, h4, h5, h6, [role="heading"]';
// The first row of each group has a hidden heading: "You sent" for the user,
// the other person's name (or "<Name> sent") for theirs. The rest of the
// group has none and belongs to the same sender.
var YOU_SENT = /^You (sent|replied|unsent)/i;
var THEY_SENT = /^(.+?) (sent|replied)\b/i;

function conversationTitle(list) {
  return (list.getAttribute('aria-label') || '').replace(CONVERSATION_PREFIX, '').trim();
}

function conversationId(list) {
  // Full-page Messenger: the thread id is in the URL. Popups: fall back to the
  // conversation's name, which is the best stable thing they expose.
  var inMain = list.closest('[role="main"]');
  var match = location.pathname.match(/\/messages\/(?:e2ee\/)?t\/([^/?#]+)/);
  if (inMain && match) return 'thread:' + match[1];
  return 'popup:' + conversationTitle(list);
}

// Message text lives in leaf `dir="auto"` elements inside the message
// (the article, when there is one), outside the heading, buttons, and
// anything hidden from screen readers.
function textNodes(row) {
  var scope = row.querySelector(MESSAGE) || row;
  var nodes = scope.querySelectorAll('[dir="auto"]');
  var result = [];
  for (var i = 0; i < nodes.length; i++) {
    var node = nodes[i];
    if (node.querySelector('[dir="auto"]')) continue;
    if (node.closest(HEADING) || node.closest('[aria-hidden="true"]')) continue;
    // Each bubble also sits in a screen-reader button that repeats the text
    // with extra wording ("Enter, …"); reading both would double every message.
    if (node.closest('[role="button"]')) continue;
    result.push(node);
  }
  return result;
}

function rowText(row) {
  return textNodes(row)
    .map(function (node) { return (node.innerText || node.textContent || '').trim(); })
    .filter(Boolean)
    .join('\n');
}

function rowAuthor(row, previous) {
  var heading = row.querySelector(HEADING);
  var label = heading ? heading.textContent.trim() : '';
  if (YOU_SENT.test(label)) return { fromUser: true, sender: null };
  if (label) {
    var named = label.match(THEY_SENT);
    return { fromUser: false, sender: named ? named[1] : label };
  }
  return previous ? { fromUser: previous.fromUser, sender: previous.sender } : null;
}

function readConversation(list) {
  var rows = list.querySelectorAll(ROW);
  var messages = [];
  var previous = null;
  for (var i = 0; i < rows.length; i++) {
    var text = rowText(rows[i]);
    if (!text) continue;
    var author = rowAuthor(rows[i], previous);
    if (!author) continue;
    previous = author;
    messages.push({
      fromUser: author.fromUser,
      sender: author.sender,
      text: text.length > MAX_TEXT ? text.slice(0, MAX_TEXT) + '…' : text,
    });
  }
  return {
    conversationId: conversationId(list),
    title: conversationTitle(list),
    url: location.href,
    messages: messages.slice(-MAX_MESSAGES),
  };
}

// ---- Sending to Dart -------------------------------------------------------

var lastSent = {}; // conversationId -> signature of the messages last sent
var timers = typeof WeakMap === 'function' ? new WeakMap() : null;

function signature(snapshot) {
  return snapshot.messages.map(function (m) {
    return (m.fromUser ? '>' : '<') + m.text;
  }).join('\u0000');
}

function send(snapshot) {
  var bridge = window.flutter_inappwebview;
  if (bridge && typeof bridge.callHandler === 'function') {
    bridge.callHandler(HANDLER, snapshot);
    return;
  }
  window.addEventListener('flutterInAppWebViewPlatformReady', function () {
    window.flutter_inappwebview.callHandler(HANDLER, snapshot);
  }, { once: true });
}

function check(list) {
  if (!list.isConnected) return;
  var snapshot = readConversation(list);
  var hasIncoming = snapshot.messages.some(function (m) { return !m.fromUser; });
  if (!hasIncoming) return;
  var sig = signature(snapshot);
  if (lastSent[snapshot.conversationId] === sig) return;
  lastSent[snapshot.conversationId] = sig;
  kwHab.log('message-monitor', 'sending', snapshot.messages.length, 'messages from', snapshot.conversationId,
    snapshot.messages.map(function (m) { return m.fromUser ? 'you' : 'them'; }).join(','));
  send(snapshot);
}

// Rows arrive in bursts (opening a conversation, history loading, typing
// indicators), so wait until the list has been quiet for SETTLE_MS.
function schedule(list) {
  if (!timers) return;
  clearTimeout(timers.get(list));
  timers.set(list, setTimeout(function () { check(list); }, SETTLE_MS));
}

// Diagnostics: a few seconds after opening Messenger, report what the
// selectors found (counts and labels only, no message text).
kwHab.onNavigate(function (loc) {
  if (!/\/messages\//.test(loc.pathname)) return;
  setTimeout(function () {
    var lists = document.querySelectorAll(CONVERSATION);
    var grids = Array.prototype.map.call(document.querySelectorAll('[role="grid"], [role="log"]'), function (g) {
      return g.getAttribute('role') + ':' + (g.getAttribute('aria-label') || '(no label)');
    });
    kwHab.log('message-monitor', 'diagnostics', JSON.stringify({
      path: loc.pathname,
      conversations: lists.length,
      rowsInConversations: lists.length ? lists[0].querySelectorAll(ROW).length : 0,
      rowsOnPage: document.querySelectorAll(ROW).length,
      grids: grids,
      messagesRead: lists.length ? readConversation(lists[0]).messages.length : 0,
      bridge: !!(window.flutter_inappwebview && window.flutter_inappwebview.callHandler),
    }));
  }, 4000);
});

kwHab.onElement(CONVERSATION, schedule);
kwHab.onElement(ROW, function (row) {
  var list = row.closest(CONVERSATION);
  if (list) schedule(list);
});

// Debug aid for whoever maintains the selectors: shows what would be sent for
// every open conversation, without sending it.
window.kwHabMessageMonitorPreview = function () {
  return Array.prototype.map.call(document.querySelectorAll(CONVERSATION), readConversation);
};
