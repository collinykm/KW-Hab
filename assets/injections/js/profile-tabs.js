// Every profile (the user's own included): open on the About tab; show only
// the About and Photos tabs (plus Reels and Groups on the user's own profile);
// hide the "See recommendations" chevron, its "People You May Know" panel and
// the "•••" button.
// css/profile-tabs.css hides whatever gets tagged and styles the added tabs.

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

// Facebook drops some tabs' href after it hydrates, so fall back to the label.
var KEPT_LABELS = { About: true, Photos: true };
var KEPT_SECTIONS = { about: true, photos: true };

// Tabs we add on the user's own profile, copied from the Photos tab so they
// look like Facebook's own.
var ADDED_TABS = [
  { section: 'reels_tab', label: 'Reels' },
  { section: 'groups', label: 'Groups' },
];

function hide(el) {
  el.setAttribute('data-kw-hidden', 'profile-tab');
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

function relabel(tab, label) {
  var walker = document.createTreeWalker(tab, NodeFilter.SHOW_TEXT);
  for (var node = walker.nextNode(); node; node = walker.nextNode()) {
    if (node.nodeValue.trim() === 'Photos') node.nodeValue = label;
  }
}

// Only the user's own profile has an "Edit profile" button.
function isOwnProfile() {
  return !!document.querySelector('[role="main"] [aria-label="Edit profile"]');
}

// Remembered so the tabs can still be added if "Edit profile" loads after them.
var profileTabs = null;

function addTabs(tablist, aboutTab, photosTab) {
  if (!isOwnProfile()) return;
  var old = tablist.querySelectorAll('[data-kw-tab]');
  for (var i = 0; i < old.length; i++) old[i].remove();

  var current = profileSection(location.href);
  var after = photosTab;
  ADDED_TABS.forEach(function (spec) {
    var tab = photosTab.cloneNode(true);
    tab.setAttribute('data-kw-tab', spec.section);
    tab.setAttribute('href', sectionUrl(aboutTab.href, spec.section));
    tab.setAttribute('aria-selected', current === spec.section ? 'true' : 'false');
    if (current === spec.section) tab.setAttribute('data-kw-active', '');
    tab.removeAttribute('data-kw-hidden');
    relabel(tab, spec.label);
    after.parentNode.insertBefore(tab, after.nextSibling);
    after = tab;
  });
}

kwHab.onElement('[role="tab"][aria-label="More profile sections"]', function (more) {
  var tablist = more.closest('[role="tablist"]');
  if (!tablist) return;
  hide(more);

  var aboutTab = null;
  var photosTab = null;
  var tabs = tablist.querySelectorAll('[role="tab"]:not([data-kw-tab])');
  for (var i = 0; i < tabs.length; i++) {
    var href = tabs[i].getAttribute('href');
    var label = tabs[i].innerText.trim();
    var section = href ? profileSection(href) : null;
    var kept = section ? KEPT_SECTIONS[section] : KEPT_LABELS[label];
    if (!kept) {
      hide(tabs[i]);
      continue;
    }
    if (section === 'about' || label === 'About') aboutTab = tabs[i];
    if (section === 'photos' || label === 'Photos') photosTab = tabs[i];
  }
  if (!aboutTab || !aboutTab.href) return;

  if (photosTab) {
    profileTabs = { tablist: tablist, about: aboutTab, photos: photosTab };
    addTabs(tablist, aboutTab, photosTab);
  }

  // Land on About instead of the All (posts) view. replace() keeps the All
  // view out of history, so Back doesn't bounce the user straight here again.
  if (profileSection(location.href) === 'all') {
    location.replace(aboutTab.href);
  }
});

// "Edit profile" can render after the tab bar; add the own-profile tabs then.
kwHab.onElement('[role="main"] [aria-label="Edit profile"]', function () {
  if (!profileTabs || !profileTabs.tablist.isConnected) return;
  if (profileTabs.tablist.querySelector('[data-kw-tab]')) return;
  addTabs(profileTabs.tablist, profileTabs.about, profileTabs.photos);
});

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
