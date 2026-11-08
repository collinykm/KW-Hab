// Messenger's chat list (the "Thread list" panel on /messages). Most of it is
// css/chat-list.css; this file does what CSS can't:
//   - hides the Marketplace chats folder. It is a row like the others, told
//     apart only by its text and by being a button rather than a link to a
//     conversation;
//   - with the All / Unread / Groups / Communities tabs hidden, makes sure All
//     is the one showing, so no chats are filtered out of sight.

var ROW = '[role="grid"][aria-label="Chats"] [role="row"]';
var HIDDEN = 'data-kw-chat-list-hidden';
var TABS = '[role="navigation"][aria-label="Thread list"] [role="tab"]';

function isMarketplace(row) {
  if (row.querySelector('a[href*="/messages/"]')) return false;
  var spans = row.querySelectorAll('span');
  for (var i = 0; i < spans.length; i++) {
    if (!spans[i].children.length && spans[i].textContent.trim() === 'Marketplace') return true;
  }
  return false;
}

// The list reuses rows as it re-renders, so a row is re-checked rather than
// marked once.
function checkRow(row) {
  if (isMarketplace(row)) {
    if (!row.hasAttribute(HIDDEN)) row.setAttribute(HIDDEN, '');
  } else if (row.hasAttribute(HIDDEN)) {
    row.removeAttribute(HIDDEN);
  }
}

function showAll() {
  var tabs = document.querySelectorAll(TABS);
  for (var i = 0; i < tabs.length; i++) {
    var tab = tabs[i];
    if (tab.getAttribute('aria-selected') !== 'true') continue;
    if (tab.textContent.trim() === 'All') return;
    for (var j = 0; j < tabs.length; j++) {
      if (tabs[j].textContent.trim() === 'All') {
        tabs[j].click();
        kwHab.log('chat-list', 'switched the chat list back to All');
        return;
      }
    }
  }
}

kwHab.onElement(ROW, checkRow);
setInterval(function () {
  if (location.pathname.indexOf('/messages') !== 0) return;
  document.querySelectorAll(ROW).forEach(checkRow);
  showAll();
}, 1000);
