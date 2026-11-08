// Comment sections (post dialogs, the feed, reels). See css/comments.css for
// what is hidden and resized.
//
// Author row: keeps only the name next to the profile picture. The rest of
// the row (" · 1d" timestamp, badges) is marked hidden.
// Actions under a comment: the Share button is hidden, and hovering Like no
// longer pops up the row of emoji reactions (clicking it still likes).
// Sort menu: the "Most relevant" / "Newest" / "All comments" button is hidden.
// Count: the "6 of 1,205" next to "View more comments" is hidden.
// Comment box: the send button gets a "Send" label under its icon, and the
// user's avatar stops being a switch-profile button.

var HIDDEN = 'data-kw-comments-hidden';
var COMMENT = '[role="article"][aria-label]';
var COMMENT_LABEL = /^(Comment|Reply) by /;
var SORT_LABEL = /^(Most relevant|Newest|All comments|Top comments|Most recent)$/i;
var MORE_LABEL = /^View (more|previous) comments$/i;
var COUNT_LABEL = /^\d[\d,.]*\s+of\s+\d[\d,.]*\s*[KMB]?$/i;
var SWITCH_PROFILE = '[role="button"][aria-label="Switch to a different profile or Page"]';
var REACTIONS_POPUP = 'div[role="dialog"][aria-label="Reactions"]';

function isComment(el) {
  return !!el && COMMENT_LABEL.test(el.getAttribute('aria-label') || '');
}

// ---- Author row -----------------------------------------------------------

// Every comment has a timestamp link (to ?comment_id=…) in the author row,
// next to the name. It appears with the comment, so it is the hook.
kwHab.onElement(COMMENT + ' a[href*="comment_id="]', function (time) {
  var comment = time.closest(COMMENT);
  if (!comment || !COMMENT_LABEL.test(comment.getAttribute('aria-label'))) return;

  // The visible name link (the avatar's link is aria-hidden).
  var name = comment.querySelector('a[role="link"][aria-hidden="false"]');
  if (!name || name.contains(time)) return;
  name.classList.add('kw-comments-name');

  // Climb from the name to the child of the row that also holds the timestamp,
  // then hide every other child of that row.
  var cell = name;
  while (cell.parentElement && cell.parentElement !== comment && !cell.parentElement.contains(time)) {
    cell = cell.parentElement;
  }
  var row = cell.parentElement;
  if (!row || row === comment) return;
  Array.prototype.forEach.call(row.children, function (child) {
    if (child !== cell) child.setAttribute(HIDDEN, '');
  });
});

// ---- Actions under a comment ----------------------------------------------

// Each action (Reply, Share, Edited) is a text button in its own
// <div><li role="presentation">. Reply gets a box (css), Share is hidden.
kwHab.onElement(COMMENT + ' li[role="presentation"] [role="button"]', function (button) {
  var text = button.textContent.trim();
  if (text === 'Reply') button.classList.add('kw-comments-reply');
  if (text !== 'Share') return;
  var item = button.closest('li');
  var box = item.parentElement && item.parentElement.children.length === 1 ? item.parentElement : item;
  box.setAttribute(HIDDEN, '');
});

// Hovering (or focusing) Like opens a new Reactions popup in a layer at the
// top of the page, so the popup itself doesn't say what opened it. Remember
// what the pointer or focus was last on, and hide popups opened from a comment.
// Posts keep their popup.
var lastTarget = null;
function remember(e) { lastTarget = e.target; }
document.addEventListener('pointerover', remember, true);
document.addEventListener('focusin', remember, true);

kwHab.onElement(REACTIONS_POPUP, function (popup) {
  if (lastTarget && lastTarget.closest && isComment(lastTarget.closest(COMMENT))) {
    popup.setAttribute(HIDDEN, '');
  }
});

// ---- Sort menu ------------------------------------------------------------

kwHab.onElement('[role="button"][aria-haspopup="menu"]:not([aria-label])', function (button) {
  if (!SORT_LABEL.test(button.textContent.trim())) return;
  // Hide the button's wrapper too, so its padding goes with it.
  var box = button;
  while (box.parentElement && box.parentElement.children.length === 1) box = box.parentElement;
  box.setAttribute(HIDDEN, '');
});

// ---- Comment count --------------------------------------------------------

// "View more comments" sits in a row whose other side reads "6 of 1,205".
// Climb a few levels from the button looking for that count beside it.
kwHab.onElement('[role="button"]:not([aria-label])', function (button) {
  if (!MORE_LABEL.test(button.textContent.trim())) return;
  var node = button;
  for (var depth = 0; depth < 4 && node.parentElement; depth++) {
    var row = node.parentElement;
    for (var i = 0; i < row.children.length; i++) {
      var child = row.children[i];
      if (child !== node && COUNT_LABEL.test(child.textContent.trim())) child.setAttribute(HIDDEN, '');
    }
    node = row;
  }
});

// ---- Own avatar -----------------------------------------------------------

// Make the switch-profile button a plain picture: out of the tab order, read
// as an image, and without the notch its chevron badge cuts into the photo.
kwHab.onElement(SWITCH_PROFILE, function (button) {
  button.classList.add('kw-comments-own-avatar');
  button.setAttribute('tabindex', '-1');
  button.setAttribute('role', 'img');
  button.setAttribute('aria-label', 'Your profile picture');
  button.removeAttribute('aria-haspopup');
  button.querySelectorAll('mask circle[data-visualcompletion="ignore"]').forEach(function (notch) {
    notch.setAttribute('r', '0');
  });
});

// ---- Send button ----------------------------------------------------------

kwHab.onElement('#focused-state-composer-submit [role="button"]', function (button) {
  if (button.querySelector('.kw-comments-send-label')) return;
  var label = document.createElement('span');
  label.className = 'kw-comments-send-label';
  label.setAttribute('aria-hidden', 'true'); // the button is already labelled
  label.textContent = 'Send';
  button.appendChild(label);
});
