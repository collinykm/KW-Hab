// The tab bar on profiles, and the buttons around it.
//
// Other people's profiles keep All (their intro and posts), About, Friends,
// Photos and Reels. Everything else, including the More menu (Check-ins,
// Music, Sports, Movies, Likes, Events, Reviews given, …), is hidden.
//
// The user's own profile opens on About and keeps About, Photos and Reels,
// plus a Groups tab added here.
//
// On every profile the "See recommendations" chevron is hidden, along with
// the "People You May Know" panel it opens, and so is the "•••" button (on
// other people's profiles js/profile-actions.js replaces it with labelled
// Block and Report buttons).
// css/profile-tabs.css hides whatever gets tagged and styles the added tab.

// The tab a profile link points to: "all" (the bare profile), or its section
// name, from either ?sk=<section> or /<username>/<section>.
function profileSection(href) {
  var url = new URL(href, location.origin);
  var sk = url.searchParams.get('sk');
  if (sk) return sk;
  var parts = url.pathname.split('/').filter(Boolean);
  if (parts[0] === 'profile.php' || parts.length === 1) return 'all';
  return parts[parts.length - 1];
}

// Which Facebook tab this is. Facebook drops the tabs' href after it
// hydrates, so fall back to the label.
var SECTION_BY_LABEL = { All: 'all', About: 'about', Friends: 'friends', Photos: 'photos', Reels: 'reels_tab' };
function tabSection(tab) {
  var href = tab.getAttribute('href');
  return href ? profileSection(href) : SECTION_BY_LABEL[tab.textContent.trim()] || null;
}

var KEPT_SECTIONS = {
  own: { about: true, photos: true, reels_tab: true },
  other: { all: true, about: true, friends: true, photos: true, reels_tab: true },
};

var HIDDEN = 'data-kw-hidden';

function hide(el) {
  el.setAttribute(HIDDEN, 'profile-tab');
}

// Only the user's own profile has an "Edit profile" button.
function isOwnProfile() {
  return !!document.querySelector('[role="main"] [aria-label="Edit profile"]');
}

// The same profile's URL for another section, built from the About tab's link.
function sectionUrl(aboutHref, section) {
  var url = new URL(aboutHref, location.origin);
  if (!url.searchParams.get('sk')) {
    // /<username>/about -> /<username>
    url.pathname = url.pathname.replace(/\/about\/?$/, '');
  }
  url.searchParams.set('sk', section);
  return url.href;
}

function relabel(tab, from, label) {
  var walker = document.createTreeWalker(tab, NodeFilter.SHOW_TEXT);
  for (var node = walker.nextNode(); node; node = walker.nextNode()) {
    if (node.nodeValue.trim() === from) node.nodeValue = label;
  }
}

// Sort the tabs into kept and hidden. "Edit profile" can render after the tab
// bar, so this runs again then, and starts from a clean slate each time.
function setUpTabs(tablist) {
  if (!tablist || !tablist.isConnected) return;
  var own = isOwnProfile();
  var kept = own ? KEPT_SECTIONS.own : KEPT_SECTIONS.other;
  var found = { about: null, photos: null, reels: null };

  var tabs = tablist.querySelectorAll('[role="tab"]:not([data-kw-tab])');
  for (var i = 0; i < tabs.length; i++) {
    var tab = tabs[i];
    if (tab.getAttribute('aria-label') === 'More profile sections') {
      hide(tab);
      continue;
    }
    var section = tabSection(tab);
    if (section === 'about') found.about = tab;
    if (section === 'photos') found.photos = tab;
    if (section === 'reels_tab') found.reels = tab;
    if (kept[section]) tab.removeAttribute(HIDDEN);
    else hide(tab);
  }

  if (!own || !found.about || !found.about.href || !found.photos) return;
  addGroupsTab(tablist, found);

  // Own profile: land on About instead of the All (posts) view. replace()
  // keeps the All view out of history, so Back doesn't bounce the user
  // straight here again.
  if (profileSection(location.href) === 'all') location.replace(found.about.href);
}

// Own profile only: a Groups tab. Facebook only has Groups inside its "More"
// menu, which won't open for scripted clicks, so this Groups tab is a plain
// link and does a full page load.
function addGroupsTab(tablist, found) {
  if (tablist.querySelector('[data-kw-tab]')) return;
  // Copy a tab that isn't selected, so the copy doesn't inherit its highlight.
  var template = found.photos.getAttribute('aria-selected') === 'true' ? found.about : found.photos;
  var groups = template.cloneNode(true);
  groups.setAttribute('data-kw-tab', 'groups');
  groups.setAttribute('href', sectionUrl(found.about.href, 'groups'));
  groups.removeAttribute(HIDDEN);
  relabel(groups, template === found.about ? 'About' : 'Photos', 'Groups');
  var after = found.reels || found.photos;
  after.parentNode.insertBefore(groups, after.nextSibling);
  markActiveTab();
}

// Highlight our Groups tab on the Groups page. Facebook's own tabs switch
// without a reload, so this has to follow every in-app navigation.
function markActiveTab() {
  var groups = document.querySelector('[data-kw-tab="groups"]');
  if (!groups) return;
  var active = profileSection(location.href) === 'groups';
  groups.setAttribute('aria-selected', active ? 'true' : 'false');
  if (active) groups.setAttribute('data-kw-active', '');
  else groups.removeAttribute('data-kw-active');
}

// The profile's tab bar: the tab list in main with an About tab. (Not every
// profile has a More tab; tab lists inside a page, like About's subsections,
// have no About tab.)
function isProfileTabBar(tablist) {
  var tabs = tablist.querySelectorAll('[role="tab"]');
  for (var i = 0; i < tabs.length; i++) {
    if (tabSection(tabs[i]) === 'about') return true;
  }
  return false;
}

function currentTablist() {
  var lists = document.querySelectorAll('[role="main"] [role="tablist"]');
  for (var i = 0; i < lists.length; i++) {
    if (isProfileTabBar(lists[i])) return lists[i];
  }
  return null;
}

// Tabs render one by one; sort them once the bar has settled.
var tabsPending = null;
function setUpTabsSoon() {
  if (tabsPending) return;
  tabsPending = setTimeout(function () {
    tabsPending = null;
    setUpTabs(currentTablist());
  }, 50);
}

kwHab.onElement('[role="main"] [role="tablist"] [role="tab"]', setUpTabsSoon);
kwHab.onElement('[role="main"] [aria-label="Edit profile"]', setUpTabsSoon);
kwHab.onNavigate(markActiveTab);

// The chevron next to the profile's buttons, and the "•••" (on other
// people's profiles js/profile-actions.js puts its Block and Report items
// on labelled buttons).
kwHab.onElement(
  '[role="main"] [aria-label="See recommendations"], ' +
    '[role="main"] [aria-label="Profile settings see more options"]',
  hide
);

// The "People You May Know" panel that chevron opens. With the chevron gone it
// could never be closed, so hide the whole card: climb from its heading to the
// box holding the suggestion cards, then through wrappers of the same height
// (the card's frame), stopping before the much taller profile header.
kwHab.onElement('[role="main"] h2', function (heading) {
  if (heading.textContent.trim() !== 'People You May Know') return;
  var main = heading.closest('[role="main"]');
  var panel = heading;
  while (panel !== main && !panel.querySelector('[aria-label^="Remove recommendation for"]')) {
    panel = panel.parentElement;
  }
  if (panel === main) return;
  while (panel.parentElement !== main && panel.parentElement.offsetHeight <= panel.offsetHeight + 10) {
    panel = panel.parentElement;
  }
  hide(panel);
});
