// Every profile (the user's own included): open on the About tab; show only
// the About and Photos tabs (plus Reels and Groups on the user's own profile);
// hide the "See recommendations" chevron, its "People You May Know" panel and
// the "•••" button.
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

// Which Facebook tab this is. Facebook drops some tabs' href after it
// hydrates, so fall back to the label.
var SECTION_BY_LABEL = { About: 'about', Photos: 'photos', Reels: 'reels_tab' };
function tabSection(tab) {
  var href = tab.getAttribute('href');
  return href ? profileSection(href) : SECTION_BY_LABEL[tab.textContent.trim()] || null;
}

var KEPT_SECTIONS = { about: true, photos: true };

function hide(el) {
  el.setAttribute('data-kw-hidden', 'profile-tab');
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

// The current profile's tab bar and Facebook's own tabs in it.
var profileTabs = null;

// Own profile only: show Facebook's real Reels tab (it switches instantly),
// and add a Groups tab. Facebook only has Groups inside its "More" menu, which
// won't open for scripted clicks, so this Groups tab is a plain link and does
// a full page load.
function addOwnProfileTabs() {
  var t = profileTabs;
  if (!t || !t.tablist.isConnected || !isOwnProfile()) return;
  if (t.tablist.querySelector('[data-kw-tab]')) return;

  if (t.reels) t.reels.removeAttribute('data-kw-hidden');

  // Copy a tab that isn't selected, so the copy doesn't inherit its highlight.
  var template = t.photos.getAttribute('aria-selected') === 'true' ? t.about : t.photos;
  var groups = template.cloneNode(true);
  groups.setAttribute('data-kw-tab', 'groups');
  groups.setAttribute('href', sectionUrl(t.about.href, 'groups'));
  groups.removeAttribute('data-kw-hidden');
  relabel(groups, template === t.about ? 'About' : 'Photos', 'Groups');
  var after = t.reels || t.photos;
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

kwHab.onElement('[role="tab"][aria-label="More profile sections"]', function (more) {
  var tablist = more.closest('[role="tablist"]');
  if (!tablist) return;
  hide(more);

  var found = { tablist: tablist, about: null, photos: null, reels: null };
  var tabs = tablist.querySelectorAll('[role="tab"]:not([data-kw-tab])');
  for (var i = 0; i < tabs.length; i++) {
    var section = tabSection(tabs[i]);
    if (section === 'about') found.about = tabs[i];
    if (section === 'photos') found.photos = tabs[i];
    if (section === 'reels_tab') found.reels = tabs[i];
    if (!KEPT_SECTIONS[section]) hide(tabs[i]);
  }
  if (!found.about || !found.about.href || !found.photos) return;
  profileTabs = found;
  addOwnProfileTabs();

  // Land on About instead of the All (posts) view. replace() keeps the All
  // view out of history, so Back doesn't bounce the user straight here again.
  if (profileSection(location.href) === 'all') {
    location.replace(found.about.href);
  }
});

// "Edit profile" can render after the tab bar; add the own-profile tabs then.
kwHab.onElement('[role="main"] [aria-label="Edit profile"]', addOwnProfileTabs);
kwHab.onNavigate(markActiveTab);

// The chevron and "•••" buttons next to the profile actions and the tabs.
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
