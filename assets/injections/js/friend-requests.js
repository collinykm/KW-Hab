// The top bar's Friends tab opens the user's own friends grid instead of
// Facebook's Friends home page (js/top-bar.js). The grid's Friends card has
// its own "Friend requests" link. This
//   - points it at the requests page (/friends/requests/), not Facebook's
//     Friends home page, where requests sit above "People you may know";
//   - adds the number of new requests Facebook puts on the Friends tab
//     ("Friends, 3 new requests") to it, as a red badge, since the tab no
//     longer leads to the requests.

var REQUESTS_PATH = '/friends/requests/';
var LINK = 'kw-friend-requests-link';

var FRIENDS_TAB = 'div[role="navigation"][aria-label="Facebook"] a[aria-label^="Friends"]';

// "Friends, 3 new requests" -> 3.
function newRequests() {
  var tab = document.querySelector(FRIENDS_TAB);
  var m = tab && tab.getAttribute('aria-label').match(/(\d+)/);
  return m ? Number(m[1]) : 0;
}

// The "Friend requests" link in main (on the friends grid, the card's).
function requestsLink() {
  var links = document.querySelectorAll('[role="main"] a[href*="/friends/requests"], [role="main"] [role="link"]');
  for (var i = 0; i < links.length; i++) {
    if (links[i].textContent.replace(/\d+$/, '').trim() === 'Friend requests') return links[i];
  }
  return null;
}

function update() {
  var link = requestsLink();
  if (!link) return;
  link.classList.add(LINK);
  if (link.getAttribute('href') !== REQUESTS_PATH) link.setAttribute('href', REQUESTS_PATH);
  var badge = link.querySelector('.kw-friend-requests-count');
  var n = newRequests();
  if (!n) {
    if (badge) badge.remove();
    return;
  }
  if (!badge) {
    badge = document.createElement('span');
    badge.className = 'kw-friend-requests-count';
    badge.setAttribute('aria-hidden', 'true');
    // Inside the link's innermost text box, so it sits on the same line.
    var walker = document.createTreeWalker(link, NodeFilter.SHOW_TEXT);
    var text = null;
    for (var node = walker.nextNode(); node; node = walker.nextNode()) {
      if (node.nodeValue.trim() === 'Friend requests') text = node;
    }
    (text ? text.parentNode : link).appendChild(badge);
  }
  badge.textContent = String(n);
}

// Ahead of Facebook's own handler, which would open its Friends home page.
document.addEventListener('click', function (e) {
  if (!e.target.closest || !e.target.closest('.' + LINK)) return;
  e.preventDefault();
  e.stopImmediatePropagation();
  location.href = REQUESTS_PATH;
}, true);

var pending = null;
function updateSoon() {
  if (pending) return;
  pending = setTimeout(function () {
    pending = null;
    update();
  }, 50);
}

kwHab.onElement('[role="main"] a, [role="main"] [role="link"]', updateSoon);
kwHab.onElement(FRIENDS_TAB, updateSoon);
kwHab.onNavigate(updateSoon);
