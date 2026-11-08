// The ⋯ menu on posts. css/post-menu.css hides it on other people's posts;
// this file
//   - marks the user's own posts' menus [data-kw-own-post], so they stay;
//   - adds a "Save" button after Send in each post's Like / Comment / Send
//     row (css/post-menu.css labels all four and makes the row taller). It works the hidden menu: opens it unseen, clicks "Save post" (or
//     "Unsave post"), and shows "Saved" afterwards.
//
// Facebook doesn't tell the page whether a post is already saved until its
// menu is opened, so the button starts as "Save". Pressing it on a post that
// was already saved just shows "Saved".

var POST_MENU = '[role="button"][aria-label^="Actions for this post"]';
var OWN = 'data-kw-own-post';
var BUSY = 'data-kw-post-menu-busy';
var SAVED = 'data-kw-saved';
var SAVE_ITEM = /^(Save|Unsave) (post|video|link|photo|event|reel)\b/i;
var NAME_KEY = 'kw-own-name';
var SVG_NS = 'http://www.w3.org/2000/svg';

// ---- Whose post ----------------------------------------------------------
// The menu's label ends in the author's name. The user's own name comes from
// a link to their profile (its href holds their c_user id), or failing that
// the first name in "What's on your mind, <name>?". It is remembered, since
// neither is on every page.

function ownId() {
  var m = document.cookie.match(/(?:^|;\s*)c_user=(\d+)/);
  return m ? m[1] : null;
}

// Links to the user's own profile that are buttons, not their name ("Edit
// profile" on their profile page links there too).
var NOT_A_NAME = /^(Edit profile|View( your)? profile|See all|See more|Profile|Posts|About|Friends|Photos|Reels|Groups|Edit|Add to story)$/i;

function storedName() {
  var name = null;
  try { name = localStorage.getItem(NAME_KEY); } catch (e) { /* private mode */ }
  // A wrong guess remembered before NOT_A_NAME existed is forgotten.
  return name && !NOT_A_NAME.test(name) ? name : null;
}

function storeName(name) {
  var stored = storedName();
  if (!name || name === stored) return;
  // Keep a full name over its first name ("Lucas Guo" over "Lucas"): with only
  // a first name, any post by someone else with that first name counts as own.
  if (stored && stored.indexOf(name + ' ') === 0) return;
  try { localStorage.setItem(NAME_KEY, name); } catch (e) { /* private mode */ }
  kwHab.log('post-menu', 'own name:', name);
  document.querySelectorAll(POST_MENU).forEach(markIfOwn);
}

function learnName() {
  var id = ownId();
  if (id) {
    var links = document.querySelectorAll('a[href*="' + id + '"]');
    for (var i = 0; i < links.length; i++) {
      var text = (links[i].textContent || '').trim();
      if (!text || text.length >= 60 || /\d/.test(text) || NOT_A_NAME.test(text)) continue;
      if (/edit/i.test(links[i].getAttribute('href') || '')) continue;
      return storeName(text);
    }
  }
}

kwHab.onElement('[role="button"]', function (button) {
  var m = (button.textContent || '').trim().match(/^What's on your mind, (.+)\?$/i);
  if (m && !storedName()) storeName(m[1]);
});
kwHab.onNavigate(function () { setTimeout(learnName, 1500); });

function markIfOwn(menu) {
  var name = storedName();
  if (!name) return;
  var label = menu.getAttribute('aria-label') || '';
  var by = label.replace(/^Actions for this post( by )?/, '');
  if (by === name || by.indexOf(name + ' ') === 0) menu.setAttribute(OWN, '');
}

kwHab.onElement(POST_MENU, markIfOwn);

// ---- Action row and Save button ------------------------------------------
// The row holds Like (grouped with the "React to" picker), Comment and Send /
// Share. Each is marked [data-kw-action] for css/post-menu.css to label, and
// the row .kw-post-actions. Facebook's labels vary ("Comment on X's post, 38
// comments" / "Leave a comment"; some posts have "Send", others "Share X's
// post"), and they can be set after the button appears, so rows are also
// re-checked every second.

var ACTIONS = [
  ['like', /^(React with Like|Like$|Remove Like|Unlike|Change .*reaction)/i],
  ['comment', /^(Comment on |Leave a comment|Comment$)/i],
  ['send', /^(Send$|Send this to friends)/i],
  ['share', /^Share\b/i],
];
var COMMENT_BUTTONS = '[role="button"][aria-label^="Comment on "], [role="button"][aria-label^="Leave a comment"], [role="button"][aria-label="Comment"]';

function actionOf(button) {
  var label = button.getAttribute('aria-label') || '';
  for (var i = 0; i < ACTIONS.length; i++) {
    if (ACTIONS[i][1].test(label)) return ACTIONS[i][0];
  }
  return null;
}

function find(root, action) {
  var buttons = root.querySelectorAll('[role="button"][aria-label]');
  for (var i = 0; i < buttons.length; i++) {
    if (!buttons[i].classList.contains('kw-save') && actionOf(buttons[i]) === action) return buttons[i];
  }
  return null;
}

// The lowest ancestor of the Comment button that also holds Like and Send.
function rowOf(comment) {
  var el = comment.parentElement;
  for (var depth = 0; el && depth < 6; depth++, el = el.parentElement) {
    if ((find(el, 'send') || find(el, 'share')) && find(el, 'like')) return el;
  }
  return null;
}

// The child of row that holds el.
function slotIn(row, el) {
  while (el && el.parentElement !== row) el = el.parentElement;
  return el;
}

// The post the row belongs to: the nearest ancestor with a post menu.
function menuFor(row) {
  for (var el = row; el; el = el.parentElement) {
    var menu = el.querySelector(POST_MENU);
    if (menu) return menu;
  }
  return null;
}

function setUpRow(comment) {
  if (comment.closest('[role="article"][aria-label^="Comment"], [role="article"][aria-label^="Reply"]')) return;
  var row = rowOf(comment);
  if (!row) return;
  if (!row.classList.contains('kw-post-actions')) {
    row.classList.add('kw-post-actions');
    // The wrappers around the row have a fixed height, which would cut off
    // the labels. Free the ones that hold only the row.
    for (var el = row.parentElement, depth = 0; el && depth < 4 && el.children.length === 1; el = el.parentElement, depth++) {
      el.classList.add('kw-post-actions-wrap');
    }
  }
  row.querySelectorAll('[role="button"][aria-label]').forEach(function (button) {
    if (button.classList.contains('kw-save')) return;
    var action = actionOf(button);
    if (action && button.getAttribute('data-kw-action') !== action) button.setAttribute('data-kw-action', action);
  });

  if (row.querySelector('[data-kw-save-slot]') || !menuFor(row)) return;
  var slot = slotIn(row, find(row, 'send') || find(row, 'share'));
  if (slot) row.insertBefore(makeSaveSlot(slot), slot.nextSibling);
}

function sweep() {
  document.querySelectorAll(COMMENT_BUTTONS).forEach(setUpRow);
}

kwHab.onElement(COMMENT_BUTTONS, setUpRow);
setInterval(sweep, 1000);

function bookmarkIcon() {
  var svg = document.createElementNS(SVG_NS, 'svg');
  svg.setAttribute('viewBox', '0 0 24 24');
  svg.setAttribute('class', 'kw-save-icon');
  svg.setAttribute('aria-hidden', 'true');
  var path = document.createElementNS(SVG_NS, 'path');
  path.setAttribute('d', 'M6.5 3h11A1.5 1.5 0 0 1 19 4.5V21l-7-4.5L5 21V4.5A1.5 1.5 0 0 1 6.5 3z');
  path.setAttribute('fill', 'none');
  path.setAttribute('stroke', 'currentColor');
  path.setAttribute('stroke-width', '2');
  path.setAttribute('stroke-linejoin', 'round');
  svg.appendChild(path);
  return svg;
}

function setSaved(button, saved) {
  if (saved) button.setAttribute(SAVED, '');
  else button.removeAttribute(SAVED);
  button.setAttribute('aria-label', saved ? 'Saved. Press to unsave' : 'Save post');
}

// A copy of the Send / Share slot (same size and hover), with a bookmark
// icon in its place. Its label ("Save" / "Saved") is drawn by css/post-menu.css.
function makeSaveSlot(slot) {
  var copy = slot.cloneNode(true);
  copy.setAttribute('data-kw-save-slot', '');
  var button = copy.querySelector('[data-kw-action]') || copy.querySelector('[role="button"]');
  button.removeAttribute('data-kw-action');
  button.classList.add('kw-save');
  button.setAttribute('tabindex', '0');

  var icon = button.querySelector('i, svg');
  var content = icon ? icon.parentElement : button.firstElementChild;
  content.textContent = '';
  content.appendChild(bookmarkIcon());
  setSaved(button, false);

  button.addEventListener('click', function (e) {
    e.preventDefault();
    e.stopPropagation();
    toggleSave(button);
  });
  button.addEventListener('keydown', function (e) {
    if (e.key !== 'Enter' && e.key !== ' ') return;
    e.preventDefault();
    toggleSave(button);
  });
  return copy;
}

// Diagnostics: a post whose menu was hidden but whose row wasn't found has
// its buttons' labels logged, so new label wordings can be added above.
var reported = 0;
kwHab.onElement(POST_MENU, function (menu) {
  setTimeout(function () {
    if (reported >= 6 || !menu.isConnected || menu.hasAttribute(OWN)) return;
    var post = menu;
    for (var depth = 0; post.parentElement && depth < 25; depth++) {
      if (post.parentElement.querySelectorAll(POST_MENU).length > 1) break;
      post = post.parentElement;
    }
    if (post.querySelector('.kw-post-actions')) return;
    reported++;
    var labels = [];
    post.querySelectorAll('[role="button"][aria-label]').forEach(function (b) {
      labels.push(b.getAttribute('aria-label').slice(0, 50));
    });
    kwHab.log('post-menu', 'no action row found for', menu.getAttribute('aria-label'), '| buttons:', labels.join(' / '));
  }, 4000);
});

// ---- Reactions popup -----------------------------------------------------
// Hovering Like opens a Reactions popup (Love, Care, Haha, …) in a layer at
// the top of the page, so the popup doesn't say what opened it. Remember what
// the pointer or focus was last on, and hide popups opened from an action
// row: Like then only likes and unlikes. (js/reels.js and js/comments.js do
// the same for reels and comments.)

var lastTarget = null;
function remember(e) { lastTarget = e.target; }
document.addEventListener('pointerover', remember, true);
document.addEventListener('focusin', remember, true);

kwHab.onElement('div[role="dialog"][aria-label="Reactions"]', function (popup) {
  if (lastTarget && lastTarget.closest && lastTarget.closest('.kw-post-actions')) {
    popup.setAttribute('data-kw-post-menu-hidden', '');
    kwHab.log('post-menu', 'hid the Reactions popup');
  }
});

// ---- Working the hidden menu ---------------------------------------------

function waitFor(find, timeout) {
  return new Promise(function (resolve) {
    var start = Date.now();
    (function poll() {
      var found = find();
      if (found || Date.now() - start > timeout) return resolve(found || null);
      setTimeout(poll, 50);
    })();
  });
}

function findSaveItem() {
  var items = document.querySelectorAll('[role="menu"] [role="button"], [role="menu"] [role="menuitem"]');
  for (var i = 0; i < items.length; i++) {
    if (SAVE_ITEM.test((items[i].textContent || '').trim())) return items[i];
  }
  return null;
}

function closeMenu(menuButton) {
  var esc = { key: 'Escape', code: 'Escape', keyCode: 27, bubbles: true };
  (document.activeElement || document.body).dispatchEvent(new KeyboardEvent('keydown', esc));
  setTimeout(function () {
    if (menuButton.getAttribute('aria-expanded') === 'true') menuButton.click();
  }, 100);
}

var working = false;

function toggleSave(button) {
  if (working) return;
  var row = button.closest('[data-kw-save-slot]').parentElement;
  var menuButton = menuFor(row);
  if (!menuButton) return kwHab.log('post-menu', 'no menu for this post');

  working = true;
  var wantSaved = !button.hasAttribute(SAVED);
  document.documentElement.setAttribute(BUSY, '');
  menuButton.click();

  waitFor(findSaveItem, 2000).then(function (item) {
    if (!item) {
      kwHab.log('post-menu', 'no Save item in the menu');
      closeMenu(menuButton);
      return;
    }
    var isSaved = /^Unsave/i.test(item.textContent.trim());
    if (isSaved !== wantSaved) {
      item.click();
      kwHab.log('post-menu', wantSaved ? 'saved' : 'unsaved', menuButton.getAttribute('aria-label'));
    } else {
      closeMenu(menuButton);
      kwHab.log('post-menu', 'already', isSaved ? 'saved' : 'unsaved');
    }
    setSaved(button, wantSaved);
  }).finally(function () {
    setTimeout(function () {
      document.documentElement.removeAttribute(BUSY);
      working = false;
    }, 400);
  });
}
