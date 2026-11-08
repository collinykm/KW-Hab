// Each profile tab shows its own content only. Facebook stacks other tabs'
// cards under each tab's page (About is followed by Reels and Photos, Friends
// by Check-ins, and so on). Those cards are tagged, and
// css/profile-sections.css hides them.
//
//   All     -> the intro ("Personal details") and the posts; not the
//              Highlights, Photos, Friends or other preview cards
//   About   -> the About card (all its subsections)
//   Friends -> the Friends card, with only its All friends and Mutual friends
//              filters
//   Photos  -> the Photos card, without its Albums filter
//   Reels   -> the Reels card
//   Groups  -> the Groups card (the user's own profile)
//
// A filter Facebook opens a page on is never hidden, even one from the lists
// below (e.g. a profile whose friends are private opens Friends on
// "Followers"), so the page is never left without a selected filter.

// The cards Facebook stacks under a tab's page, by heading.
var CARDS = [
  'Highlights', 'Photos', 'Friends', 'Reels', 'Videos', 'Check-ins', 'Reviews given',
  'Music', 'Sports', 'Movies', 'TV shows', 'Books', 'Likes', 'Events', 'Groups',
  'Apps and games', 'People You May Know',
];

// The filters (tabs inside a card) to hide, by section. (About's own
// subsections are tabs too, some with the same names, so this is per section.)
var HIDDEN_FILTERS = {
  friends: /^(Recently Added|Following|Followers|Birthdays|Current City|Hometown|Work|College|High School)$/i,
  photos: /^Albums$/i,
};

// The profile's tab bar: the tab list in main with an About tab (not every
// profile has a More tab).
function profileTabBar() {
  var lists = document.querySelectorAll('[role="main"] [role="tablist"]');
  for (var i = 0; i < lists.length; i++) {
    var tabs = lists[i].querySelectorAll('[role="tab"]');
    for (var j = 0; j < tabs.length; j++) {
      var href = tabs[j].getAttribute('href') || '';
      if (tabs[j].textContent.trim() === 'About' || /[?&]sk=about$|\/about\/?$/.test(href)) return lists[i];
    }
  }
  return null;
}

function currentSection() {
  return new URL(location.href).searchParams.get('sk') ||
    location.pathname.split('/').filter(Boolean).slice(1).pop() || 'all';
}

// The cards each section keeps, by heading.
function keptCards(section) {
  if (section === 'all') return ['Personal details', 'Posts'];
  if (/^(about|directory_)/.test(section)) return ['About'];
  if (/^(friends|following$|followers$)/.test(section)) return ['Friends'];
  if (/^photos/.test(section)) return ['Photos'];
  if (/reels/.test(section)) return ['Reels'];
  if (section === 'groups') return ['Groups'];
  return null;
}

// The largest box around `el` that holds none of `keepers`.
function outsideOf(el, keepers) {
  var box = el;
  for (;;) {
    var parent = box.parentElement;
    if (!parent) return box;
    for (var i = 0; i < keepers.length; i++) {
      if (parent.contains(keepers[i])) return box;
    }
    box = parent;
  }
}

function headingText(h) {
  return h.textContent.trim();
}

// Facebook's script pins the left column (the intro on All) by switching it
// to position: fixed once it has scrolled to its end. With its preview cards
// gone the column is short, so it would sit pinned at the top while the posts
// scroll past. Let it scroll with the page.
var UNSTICK = 'data-kw-profile-unstick';
function unstick(keepers, main) {
  for (var i = 0; i < keepers.length; i++) {
    for (var el = keepers[i].parentElement; el && el !== main; el = el.parentElement) {
      if (/sticky|fixed/.test(getComputedStyle(el).position)) el.setAttribute(UNSTICK, '');
    }
  }
}

function trim() {
  // Facebook's own tabs switch without a reload and may reuse wrappers, so
  // start from a clean slate each time.
  var stale = document.querySelectorAll('[data-kw-hidden="profile-section"]');
  for (var s = 0; s < stale.length; s++) stale[s].removeAttribute('data-kw-hidden');

  var keep = keptCards(currentSection());
  if (!keep) return;
  var tabs = profileTabBar();
  var main = tabs && tabs.closest('[role="main"]');
  if (!main) return;
  var below = function (el) {
    return !!(tabs.compareDocumentPosition(el) & Node.DOCUMENT_POSITION_FOLLOWING) && !tabs.contains(el);
  };

  var headings = main.querySelectorAll('h2');
  var keepers = [];
  for (var i = 0; i < headings.length; i++) {
    if (below(headings[i]) && keep.indexOf(headingText(headings[i])) >= 0) keepers.push(headings[i]);
  }
  if (!keepers.length) return;

  for (var j = 0; j < headings.length; j++) {
    var heading = headings[j];
    if (keepers.indexOf(heading) >= 0 || !below(heading)) continue;
    if (CARDS.indexOf(headingText(heading)) < 0) continue;
    var box = outsideOf(heading, keepers);
    if (box.contains(tabs)) continue;
    box.setAttribute('data-kw-hidden', 'profile-section');
  }

  unstick(keepers, main);

  // Filters inside the kept cards.
  var hiddenFilters = HIDDEN_FILTERS[keep[0] === 'Friends' ? 'friends' : keep[0] === 'Photos' ? 'photos' : ''];
  if (!hiddenFilters) return;
  var filters = main.querySelectorAll('[role="tab"]');
  for (var k = 0; k < filters.length; k++) {
    var filter = filters[k];
    if (!below(filter) || filter.getAttribute('aria-selected') === 'true') continue;
    if (hiddenFilters.test(filter.textContent.trim())) filter.setAttribute('data-kw-hidden', 'profile-section');
  }
}

// Facebook adds headings and posts one by one; trim once things settle.
var pending = null;
function trimSoon() {
  if (pending) return;
  pending = setTimeout(function () {
    pending = null;
    trim();
  }, 50);
}

kwHab.onElement('[role="main"] h2', trimSoon);
kwHab.onElement('[role="main"] [role="tab"]', trimSoon);
kwHab.onNavigate(trimSoon);
