// Template for an area script. Files whose names start with "_" are ignored,
// so this one never runs. Copy it to js/<area>.js to start a new area.
//
// Each file runs in its own scope once the page's DOM is ready. An error here
// can't break other areas.

kwHab.onNavigate(function (loc) {
  // Runs on first load and on every in-app page change.
  if (loc.pathname !== '/') return;
  kwHab.log('example', 'on the home feed');
});

kwHab.onElement('div[role="banner"]', function (banner) {
  // Runs once per matching element, including ones Facebook adds later.
  banner.prepend(kwHab.fragment('_example'));
});
