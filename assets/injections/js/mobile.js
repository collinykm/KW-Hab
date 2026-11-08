// Phones (Android, iOS): marks parts of the page that css/mobile.css
// rearranges for a narrow screen but that have no stable attribute of their
// own. Does nothing at all unless the page is marked html[data-kw-mobile],
// which only the Android/iOS app sets (lib/shell/platform.dart), so the Mac
// app never runs any of it.
//
// - data-kw-chat-window: a docked Messenger chat (the small chat window
//   Facebook opens in the corner, e.g. when a message arrives). On a phone
//   it fills the screen between the top bar and the tab bar.
// - data-kw-chat-dock: the corner area holding those windows and the
//   "New message" button, lifted above the tab bar.

if (document.documentElement.hasAttribute('data-kw-mobile')) {
  // The closest fixed-position element holding el (Facebook's chat windows and
  // their dock are positioned with obfuscated classes only).
  function fixedAncestor(el) {
    for (var e = el.parentElement; e && e !== document.body; e = e.parentElement) {
      if (getComputedStyle(e).position === 'fixed') return e;
    }
    return null;
  }

  // Inside the window, the chat card (header + messages + composer) and the
  // boxes around it have fixed sizes (a 455px-high, 321px-wide card). They are
  // marked data-kw-chat-fill so they can grow, and the part holding the
  // messages and composer data-kw-chat-body so it takes up the extra height.
  function markChatWindow(button) {
    var win = fixedAncestor(button);
    if (!win) return;
    win.setAttribute('data-kw-chat-window', '');
    var dock = fixedAncestor(win);
    if (dock) dock.setAttribute('data-kw-chat-dock', '');

    var card = button.parentElement;
    while (card && card !== win && !card.querySelector('[role="log"]')) card = card.parentElement;
    if (!card || card === win) return;
    for (var e = card; e && e !== win; e = e.parentElement) e.setAttribute('data-kw-chat-fill', '');
    Array.prototype.forEach.call(card.children, function (child) {
      if (child.querySelector('[role="log"]')) child.setAttribute('data-kw-chat-body', '');
    });
  }

  kwHab.onElement('[role="button"][aria-label="Minimize chat"]', markChatWindow);
  // Facebook re-renders the card (e.g. when the first messages load); mark again.
  kwHab.onElement('[data-kw-chat-window] [role="log"]', function (log) {
    var win = log.closest('[data-kw-chat-window]');
    var button = win && win.querySelector('[role="button"][aria-label="Minimize chat"]');
    if (button) markChatWindow(button);
  });

  // A full-page Messenger conversation on screen: html[data-kw-chat-thread],
  // so the tab bar makes way for the message box. Going by the address alone
  // isn't enough: a conversation's address loaded fresh shows the chat list
  // on a narrow screen. So it also needs the chat list to be collapsed, and
  // is checked again whenever the list changes size.
  var THREAD_LIST = '[role="navigation"][aria-label="Thread list"]';
  function markChatThread() {
    var list = document.querySelector(THREAD_LIST);
    var thread = /^\/messages\/(e2ee\/)?t\//.test(location.pathname) &&
      !(list && list.getBoundingClientRect().height >= 50);
    if (thread) document.documentElement.setAttribute('data-kw-chat-thread', '');
    else document.documentElement.removeAttribute('data-kw-chat-thread');
  }
  kwHab.onNavigate(markChatThread);
  kwHab.onElement(THREAD_LIST, function (list) {
    if (window.ResizeObserver) new ResizeObserver(markChatThread).observe(list);
    markChatThread();
  });

  // Going back from a conversation to /messages/ leaves Facebook's narrow
  // layout showing "No chats selected" with the chat list squeezed to nothing
  // (it only shows the list when /messages/ is loaded fresh). So load it
  // fresh. At most once every 10 seconds, so it can never loop.
  var LIST_RELOAD_KEY = 'kw-mobile-chat-list-reload';
  function onChatHome() {
    return /^\/messages\/?$/.test(location.pathname);
  }
  function showChatList() {
    if (!onChatHome()) return;
    setTimeout(function () {
      if (!onChatHome()) return;
      var list = document.querySelector('[role="navigation"][aria-label="Thread list"]');
      if (!list || list.getBoundingClientRect().height >= 50) return;
      var last = 0;
      try { last = Number(sessionStorage.getItem(LIST_RELOAD_KEY)) || 0; } catch (e) { /* storage blocked */ }
      if (Date.now() - last < 10000) return;
      try { sessionStorage.setItem(LIST_RELOAD_KEY, String(Date.now())); } catch (e) { /* storage blocked */ }
      location.replace('/messages/');
    }, 400);
  }
  kwHab.onNavigate(showChatList);

  kwHab.onElement('[role="button"][aria-label="New message"]', function (button) {
    var dock = fixedAncestor(button);
    if (dock) dock.setAttribute('data-kw-chat-dock', '');
  });
}
