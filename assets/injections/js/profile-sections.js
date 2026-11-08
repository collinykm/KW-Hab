// Profile section pages show one thing only:
//   About  -> just the Bio (left alone when the profile has no bio)
//   Photos -> just the Photos card (not the Reels / Groups cards under it)
//   Reels  -> just the Reels card (not the Groups card under it)
//   Groups -> just the Groups card
// Every other section below the tab bar is tagged; css/profile-sections.css
// hides it.

var KEEP_BY_SECTION = { about: 'Bio', photos: 'Photos', reels_tab: 'Reels', groups: 'Groups' };

function currentSection() {
  return new URL(location.href).searchParams.get('sk') ||
    location.pathname.split('/').filter(Boolean).slice(1).pop() || 'all';
}

// The largest box around `el` that doesn't also hold `keeper`.
function outsideOf(el, keeper) {
  var box = el;
  while (box.parentElement && !box.parentElement.contains(keeper)) {
    box = box.parentElement;
  }
  return box;
}

function trim() {
  // Facebook's own tabs switch without a reload and may reuse wrappers, so
  // start from a clean slate each time.
  var stale = document.querySelectorAll('[data-kw-hidden="profile-section"]');
  for (var s = 0; s < stale.length; s++) stale[s].removeAttribute('data-kw-hidden');

  var keepTitle = KEEP_BY_SECTION[currentSection()];
  if (!keepTitle) return;
  var tabs = document.querySelector('[role="tab"][aria-label="More profile sections"]');
  var main = tabs && tabs.closest('[role="main"]');
  if (!main) return;

  var headings = main.querySelectorAll('h2');
  var keeper = null;
  for (var i = 0; i < headings.length; i++) {
    if (headings[i].textContent.trim() === keepTitle) keeper = headings[i];
  }
  if (!keeper) return;

  for (var j = 0; j < headings.length; j++) {
    var heading = headings[j];
    if (heading === keeper) continue;
    // Only sections below the tab bar, never the profile header.
    if (!(tabs.compareDocumentPosition(heading) & Node.DOCUMENT_POSITION_FOLLOWING)) continue;
    var box = outsideOf(heading, keeper);
    if (box.contains(tabs)) continue;
    box.setAttribute('data-kw-hidden', 'profile-section');
  }
}

kwHab.onElement('[role="main"] h2', trim);
kwHab.onNavigate(trim);
