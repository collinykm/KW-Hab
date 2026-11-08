// The Saved page (/saved/, opened from the top bar's Saved tab).
//   - The gear beside the "Saved" heading links to "Reminders Settings"
//     (notifications, feed reminders, saved items in Feed). It is hidden.
//   - Each saved item's "⋯" button opens a menu whose only item is Unsave. It
//     is hidden, and an "Unsave" button (a copy of the item's "Add to
//     Collection" button) takes its place. Pressing it opens the menu unseen
//     and clicks Unsave.
// css/saved.css hides what is tagged here.

var HIDDEN = 'data-kw-hidden';
var BUSY = 'data-kw-saved-busy';

function onSavedPage() {
  return location.pathname.indexOf('/saved') === 0;
}

kwHab.onElement('a[href*="/saved/settings"]', function (gear) {
  gear.setAttribute(HIDDEN, 'saved');
});

// ---- Unsave button -------------------------------------------------------

function text(el) {
  return (el.textContent || '').trim();
}

// The item's "⋯" button ("More, <item title>"), in the smallest box around
// "Add to Collection" that has one.
function moreButtonFor(add) {
  var box = add.parentElement;
  for (var depth = 0; box && depth < 5; depth++, box = box.parentElement) {
    var buttons = box.querySelectorAll('[role="button"][aria-label]');
    for (var i = 0; i < buttons.length; i++) {
      if (/^More\b/.test(buttons[i].getAttribute('aria-label'))) return buttons[i];
    }
  }
  return null;
}

function relabel(el, from, to) {
  var walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
  for (var node = walker.nextNode(); node; node = walker.nextNode()) {
    if (node.nodeValue.trim() === from) node.nodeValue = to;
  }
}

function setUp(add) {
  if (!onSavedPage() || text(add) !== 'Add to Collection') return;
  var more = moreButtonFor(add);
  if (!more || more.hasAttribute(HIDDEN)) return;

  var unsave = add.cloneNode(true);
  unsave.classList.add('kw-unsave');
  unsave.setAttribute('aria-label', 'Unsave');
  unsave.setAttribute('tabindex', '0');
  relabel(unsave, 'Add to Collection', 'Unsave');
  unsave.addEventListener('click', function (e) {
    e.preventDefault();
    e.stopPropagation();
    doUnsave(more);
  });
  unsave.addEventListener('keydown', function (e) {
    if (e.key !== 'Enter' && e.key !== ' ') return;
    e.preventDefault();
    doUnsave(more);
  });

  more.setAttribute(HIDDEN, 'saved');
  more.after(unsave);
}

kwHab.onElement('[role="main"] [role="button"]', function (button) {
  if (button.classList.contains('kw-unsave')) return;
  // The label may be filled in after the button appears.
  setUp(button);
  setTimeout(function () { setUp(button); }, 300);
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

function findUnsaveItem() {
  var items = document.querySelectorAll('[role="menuitem"], [role="menu"] [role="button"], [role="dialog"] [role="button"]');
  for (var i = 0; i < items.length; i++) {
    if (text(items[i]) === 'Unsave') return items[i];
  }
  return null;
}

var working = false;

function doUnsave(more) {
  if (working || !more.isConnected) return;
  working = true;
  document.documentElement.setAttribute(BUSY, '');
  more.click();
  waitFor(findUnsaveItem, 2000).then(function (item) {
    if (item) {
      item.click();
    } else {
      kwHab.log('saved', 'no Unsave item in the menu');
      document.body.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', keyCode: 27, bubbles: true }));
    }
  }).finally(function () {
    setTimeout(function () {
      document.documentElement.removeAttribute(BUSY);
      working = false;
    }, 400);
  });
}
