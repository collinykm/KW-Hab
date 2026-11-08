// The Reels viewer. See css/reels.css for what is hidden.
//
// Sound: reels start muted. Any reel mute button that reads "Unmute" is
// pressed, and Facebook carries that to the next reels. The button itself is
// hidden (css), so sound stays on.
// Action column: Like, Comment and Share get a word under their icon. "Save
// reel" lives in the "…" menu, so the "…" button is hidden and a Save button
// is added under Share; pressing it opens that menu unseen and picks
// "Save reel" (or "Unsave reel").
// Creator: the globe, the Follow button and the audio line are hidden.

var HIDDEN = 'data-kw-reels-hidden';
var PLAYER = '[role="group"][aria-label="Video player"]';
var OWNER_NAME = 'a[role="link"][aria-label$=", see owner profile"]';
var SAVE_ITEM = /^(Save|Unsave) reel/;

// Bookmark icon, 24x24 like Facebook's: outline (unsaved) and filled (saved).
var BOOKMARK_OUTLINE =
  'M5 4a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2v17.1c0 .8-.9 1.3-1.6.8L12 18l-5.4 3.9c-.7.5-1.6 0-1.6-.8V4z' +
  'M7 4v15.2l5-3.6 5 3.6V4H7z';
var BOOKMARK_FILLED =
  'M5 4a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2v17.1c0 .8-.9 1.3-1.6.8L12 18l-5.4 3.9c-.7.5-1.6 0-1.6-.8V4z';

function isReelPlayer(player) {
  return !!player && !!player.querySelector('[aria-label="Search Reel"]');
}

// ---- Sound ------------------------------------------------------------------

// The same button flips between "Mute" and "Unmute", so watch its label.
kwHab.onElement(PLAYER + ' [role="button"]:is([aria-label="Unmute"], [aria-label="Mute"])', function (button) {
  var lastClick = 0;
  function unmute() {
    if (button.getAttribute('aria-label') !== 'Unmute') return;
    if (!isReelPlayer(button.closest(PLAYER))) return;
    if (Date.now() - lastClick < 1000) return; // don't fight a forced mute
    lastClick = Date.now();
    button.click();
  }
  new MutationObserver(unmute).observe(button, { attributes: true, attributeFilter: ['aria-label'] });
  // Let the rest of the player (and its "Search Reel" button) render first.
  setTimeout(unmute, 0);
});

// ---- Action column ------------------------------------------------------------

// Put a word under a column button's icon, above its count.
function addLabel(button, text) {
  var label = button.querySelector('.kw-reels-label');
  if (!label) {
    var svg = button.querySelector('svg');
    if (!svg) return null;
    // The icon's box is the ancestor whose next sibling holds the count.
    var iconBox = svg;
    while (iconBox.parentElement && iconBox.parentElement !== button &&
           !iconBox.parentElement.querySelector('span[dir="auto"]')) {
      iconBox = iconBox.parentElement;
    }
    label = document.createElement('span');
    label.className = 'kw-reels-label';
    label.setAttribute('aria-hidden', 'true'); // the button is already labelled
    iconBox.after(label);
    matchCountColour(button, label);
  }
  label.textContent = text;
  return label;
}

// Facebook turns the icon and count blue (by class) while a button is active,
// e.g. Comment while the comments are open. Give the label the count's colour.
function matchCountColour(button, label) {
  function sync() {
    var count = button.querySelector('span[dir="auto"]');
    var colour = count ? getComputedStyle(count).color : '';
    if (label.style.color !== colour) label.style.color = colour;
  }
  new MutationObserver(sync).observe(button, {
    subtree: true, childList: true, attributes: true, attributeFilter: ['class'],
  });
  sync();
}

function menuItem() {
  var items = document.querySelectorAll('[role="menu"][aria-label="Video options"] [role="menuitem"]');
  for (var i = 0; i < items.length; i++) {
    if (SAVE_ITEM.test(items[i].textContent.trim())) return items[i];
  }
  return null;
}

function buildSaveButton(shareBox, more) {
  var box = shareBox.cloneNode(true);
  box.classList.add('kw-reels-save');
  box.querySelectorAll('[id]').forEach(function (el) { el.removeAttribute('id'); });
  var button = box.querySelector('[role="button"]');
  // Drop the share count.
  var count = button.querySelector('span[dir="auto"]');
  if (count) {
    var countBox = count;
    while (countBox.parentElement && countBox.parentElement !== button &&
           !countBox.parentElement.querySelector('svg')) {
      countBox = countBox.parentElement;
    }
    countBox.remove();
  }
  var path = button.querySelector('svg');
  path.innerHTML = '<path fill-rule="evenodd" d=""></path>';
  path = path.firstChild;

  var busy = false;
  function show(saved) {
    button.setAttribute('aria-label', saved ? 'Saved. Remove from saved' : 'Save');
    button.setAttribute('aria-pressed', saved ? 'true' : 'false');
    path.setAttribute('d', saved ? BOOKMARK_FILLED : BOOKMARK_OUTLINE);
    addLabel(button, saved ? 'Saved' : 'Save');
  }
  show(false);

  function toggle(e) {
    e.preventDefault();
    e.stopPropagation();
    if (busy) return;
    busy = true;
    var root = document.documentElement;
    root.setAttribute('data-kw-reels-saving', '');
    more.click();
    var started = Date.now();
    (function poll() {
      var item = menuItem();
      if (item) {
        var wasSaved = /^Unsave/.test(item.textContent.trim());
        item.click();
        show(!wasSaved);
      } else if (Date.now() - started < 3000) {
        return setTimeout(poll, 50);
      } else {
        more.click(); // no Save item: close the menu again
      }
      setTimeout(function () { root.removeAttribute('data-kw-reels-saving'); }, 300);
      busy = false;
    })();
  }
  button.addEventListener('click', toggle);
  button.addEventListener('keydown', function (e) {
    if (e.key === 'Enter' || e.key === ' ') toggle(e);
  });
  return box;
}

// The column is Like, Comment, Share and "…", each in its own box. Start from
// "…" and climb to the box whose parent also holds Like and Share.
kwHab.onElement('[role="button"][aria-label="More options"]', function (more) {
  var moreBox = more;
  var column = more.parentElement;
  for (var depth = 0; column && depth < 5; depth++) {
    if (column.querySelector('[role="button"][aria-label^="Like,"]') &&
        column.querySelector('[role="button"][aria-label^="Share,"]')) break;
    moreBox = column;
    column = column.parentElement;
  }
  if (!column || depth === 5) return;
  column.classList.add('kw-reels-actions');

  var boxes = Array.prototype.slice.call(column.children);
  var shareBox = null;
  boxes.forEach(function (box) {
    var button = box.querySelector('[role="button"][aria-label]');
    if (!button) return;
    var match = /^(Like|Comment|Share),/.exec(button.getAttribute('aria-label'));
    if (!match) return;
    addLabel(button, match[1]);
    if (match[1] === 'Share') shareBox = box;
  });

  moreBox.setAttribute(HIDDEN, '');
  if (shareBox && !column.querySelector('.kw-reels-save')) {
    column.appendChild(buildSaveButton(shareBox, more));
  }
});

// ---- Creator ------------------------------------------------------------------

// The name row is: name, globe, " · Follow". Under it is the audio line, an
// unlabelled button ("♫ Asher · Original audio").
kwHab.onElement(OWNER_NAME, function (name) {
  var nameBlock = name.closest('span[dir="ltr"]');
  if (!nameBlock) return;

  var nameCell = name.closest('h2') || name;
  while (nameCell.parentElement && nameCell.parentElement !== nameBlock &&
         nameCell.parentElement.children.length === 1) {
    nameCell = nameCell.parentElement;
  }
  var row = nameCell.parentElement;
  if (row && row !== nameBlock) {
    Array.prototype.forEach.call(row.children, function (cell) {
      if (cell !== nameCell) cell.setAttribute(HIDDEN, '');
    });
  }

  var line = nameBlock.parentElement;
  if (!line || !line.parentElement) return;
  Array.prototype.forEach.call(line.parentElement.children, function (sibling) {
    if (sibling !== line && sibling.querySelector('[role="button"]:not([aria-label])')) {
      sibling.setAttribute(HIDDEN, '');
    }
  });
});
