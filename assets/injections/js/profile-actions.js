// Other people's profiles: "Block" and "Report" buttons beside Message.
//
// Facebook keeps both inside the profile's "•••" menu ("Profile settings see
// more options"), which js/profile-tabs.js hides along with the rest of that
// menu. Each button opens the hidden menu unseen and clicks its item, so
// Facebook's own confirmation (Block) or reporting steps (Report) appear as
// usual; nothing is blocked or reported without the user confirming there.

var DOTS = '[role="main"] [role="button"][aria-label="Profile settings see more options"]';
var PROFILE_BUSY = 'data-kw-profile-menu-busy';
var PROFILE_ACTIONS = [
  { key: 'block', label: 'Block', item: /^Block\b/i,
    icon: 'M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18zM5.6 7l11.4 11.4M18.4 17L7 5.6' },
  { key: 'report', label: 'Report', item: /^(Report profile|Find support or report|Report)\b/i,
    icon: 'M5 21V4m0 0h11l-2 4 2 4H5' },
];

function actionIcon(d) {
  var ns = 'http://www.w3.org/2000/svg';
  var svg = document.createElementNS(ns, 'svg');
  svg.setAttribute('viewBox', '0 0 24 24');
  svg.setAttribute('class', 'kw-profile-action-icon');
  svg.setAttribute('aria-hidden', 'true');
  var path = document.createElementNS(ns, 'path');
  path.setAttribute('d', d);
  path.setAttribute('fill', 'none');
  path.setAttribute('stroke', 'currentColor');
  path.setAttribute('stroke-width', '2');
  path.setAttribute('stroke-linecap', 'round');
  path.setAttribute('stroke-linejoin', 'round');
  svg.appendChild(path);
  return svg;
}

// The Message button's slot in the row of profile buttons: its outermost
// wrapper that holds nothing else.
function messageSlot(message) {
  var slot = message;
  while (slot.parentElement && slot.parentElement.children.length === 1) slot = slot.parentElement;
  return slot;
}

function makeActionSlot(slot, action) {
  var copy = slot.cloneNode(true);
  copy.setAttribute('data-kw-profile-action', action.key);
  var button = copy.matches('[role="button"]') ? copy : copy.querySelector('[role="button"]');
  button.setAttribute('aria-label', action.label);
  button.setAttribute('tabindex', '0');
  var icon = button.querySelector('i, svg');
  if (icon) icon.parentNode.replaceChild(actionIcon(action.icon), icon);
  var walker = document.createTreeWalker(button, NodeFilter.SHOW_TEXT);
  for (var node = walker.nextNode(); node; node = walker.nextNode()) {
    if (node.nodeValue.trim() === 'Message') node.nodeValue = action.label;
  }
  button.addEventListener('click', function (e) {
    e.preventDefault();
    e.stopPropagation();
    runProfileAction(action);
  });
  button.addEventListener('keydown', function (e) {
    if (e.key !== 'Enter' && e.key !== ' ') return;
    e.preventDefault();
    runProfileAction(action);
  });
  return copy;
}

function addProfileActions(message) {
  var main = message.closest('[role="main"]');
  if (!main || main.querySelector('[aria-label="Edit profile"]')) return;
  if (!main.querySelector(DOTS)) return;
  var slot = messageSlot(message);
  if (!slot.parentElement || slot.parentElement.querySelector('[data-kw-profile-action]')) return;
  var after = slot;
  PROFILE_ACTIONS.forEach(function (action) {
    var copy = makeActionSlot(slot, action);
    after.parentElement.insertBefore(copy, after.nextSibling);
    after = copy;
  });
}

kwHab.onElement('[role="main"] [role="button"][aria-label="Message"]', addProfileActions);
// The "•••" can render after Message.
kwHab.onElement(DOTS, function (dots) {
  var message = dots.closest('[role="main"]').querySelector('[role="button"][aria-label="Message"]:not([data-kw-profile-action] *)');
  if (message) addProfileActions(message);
});

function waitForItem(pattern, timeout) {
  return new Promise(function (resolve) {
    var start = Date.now();
    (function poll() {
      var items = document.querySelectorAll('[role="menu"] [role="menuitem"], [role="menu"] [role="button"]');
      for (var i = 0; i < items.length; i++) {
        if (pattern.test((items[i].textContent || '').trim())) return resolve(items[i]);
      }
      if (Date.now() - start > timeout) {
        var texts = [];
        items.forEach(function (it) { texts.push((it.textContent || '').trim()); });
        return resolve({ missing: texts });
      }
      setTimeout(poll, 50);
    })();
  });
}

var profileActionBusy = false;
function runProfileAction(action) {
  if (profileActionBusy) return;
  var dots = document.querySelector(DOTS);
  if (!dots) return kwHab.log('profile-actions', 'no "•••" on this profile');
  profileActionBusy = true;
  document.documentElement.setAttribute(PROFILE_BUSY, '');
  dots.click();
  waitForItem(action.item, 2000).then(function (item) {
    if (item.missing) {
      kwHab.log('profile-actions', 'no', action.label, 'item; menu had:', item.missing.join(' | '));
      document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', code: 'Escape', keyCode: 27, bubbles: true }));
      if (dots.getAttribute('aria-expanded') === 'true') dots.click();
      return;
    }
    kwHab.log('profile-actions', action.label, '->', item.textContent.trim());
    item.click();
  }).finally(function () {
    setTimeout(function () {
      document.documentElement.removeAttribute(PROFILE_BUSY);
      profileActionBusy = false;
    }, 400);
  });
}
