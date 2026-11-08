// The "Posts" card at the top of a profile's posts is hidden whole. It held:
//   - Filters: jump to a year, or filter by who posted, privacy or tags. A
//     filter left on makes posts seem to vanish; scrolling still reaches old
//     posts.
//   - Manage posts: ticks up to 50 posts at once to archive, trash, hide or
//     re-audience. One "Select all" could remove years of posts; the ⋯ menu on
//     each post still edits or removes it.
//   - The List view / Grid view switch: the grid's tiles have none of the
//     post's buttons (Read aloud, Like, Comment, ...). If the grid is open,
//     List view is chosen first.
// Without those, only a "Posts" heading was left. css/profile-posts.css hides
// what is tagged here.

var HIDDEN = 'data-kw-hidden';
var CONTROLS = /^(Filters|Manage posts|Grid view)$/;
// Anything outside the card: a post, its menu, the composer.
var OUTSIDE = '[role="article"], [aria-label^="Actions for this post"], [aria-label^="What\'s on your mind"]';
var MAX_CARD_HEIGHT = 250;

function labelOf(el) {
  return (el.getAttribute('aria-label') || el.textContent || '').trim();
}

function hasPostsHeading(box) {
  var headings = box.querySelectorAll('h2, h3, [role="heading"]');
  for (var i = 0; i < headings.length; i++) {
    if (headings[i].textContent.trim() === 'Posts') return true;
  }
  return false;
}

// The smallest box around el that also holds the "Posts" heading, plus the
// wrappers that hold only it (the card's frame). Never a box with a post or
// the composer in it, or one taller than the card. Null if not found.
function cardOf(el) {
  var card = el;
  while (!hasPostsHeading(card)) {
    card = card.parentElement;
    if (!card || card.getAttribute('role') === 'main') return null;
  }
  while (card.parentElement && card.parentElement.children.length === 1) card = card.parentElement;
  if (card.offsetHeight > MAX_CARD_HEIGHT || card.querySelector(OUTSIDE)) return null;
  return card;
}

function showList(tab) {
  if (tab.getAttribute('aria-selected') !== 'true') return;
  var list = tab.closest('[role="tablist"]');
  var tabs = list ? list.querySelectorAll('[role="tab"]') : [];
  for (var i = 0; i < tabs.length; i++) {
    if (labelOf(tabs[i]) === 'List view') return tabs[i].click();
  }
}

kwHab.onElement('[role="main"] :is([role="button"], [role="tab"])', function (control) {
  if (control.closest('[role="dialog"], [' + HIDDEN + ']') || !CONTROLS.test(labelOf(control))) return;
  if (labelOf(control) === 'Grid view') showList(control);
  // Without the card, at least the control itself goes.
  var card = cardOf(control) || control;
  card.setAttribute(HIDDEN, 'profile-posts');
  kwHab.log('profile-posts', 'hid', card === control ? labelOf(control) : 'the Posts card');
});
