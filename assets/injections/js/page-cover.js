// Decides when css/page-cover.css's "Loading…" screen comes off: once nothing
// new has appeared on screen for a moment and Facebook's grey placeholders have
// left it. It covers a page opening and moving to another page; on
// those moves the top bar stays visible.

var READY = 'data-kw-page-ready';
var QUIET_MS = 250;
var QUIET_GROUP_MS = 900; // Facebook scrolls groups past their banner just after loading
var QUIET_NO_MAIN_MS = 1500; // pages with no main area yet, e.g. logging in
var MAX_MS = 6000;

// Views that open over the current page, or change inside it, are not new pages.
var OVER_THE_PAGE = /^\/(photo|photos|stories|watch)\b|\/(posts|permalink|photos|videos)\//;
var ONE_PAGE_SECTIONS = ['messages', 'reel'];

var root = document.documentElement;
var path = location.pathname;
var ready = false;
var quietTimer = null;
var maxTimer = null;

// Only connected while covering: onElement can't report "nothing has changed".
var changes = new MutationObserver(function (mutations) {
  if (mutations.some(addedSomethingVisible)) waitForQuiet();
});

function onScreen(box) {
  return box.width > 0 && box.height > 0 && box.bottom > 0 && box.top < window.innerHeight;
}

function addedSomethingVisible(mutation) {
  return Array.prototype.some.call(mutation.addedNodes, function (node) {
    return node.nodeType === 1 && !/^(SCRIPT|LINK|STYLE|META)$/.test(node.nodeName) &&
      onScreen(node.getBoundingClientRect());
  });
}

function placeholderOnScreen() {
  var found = document.querySelectorAll('[data-visualcompletion="loading-state"]');
  for (var i = 0; i < found.length; i++) {
    if (onScreen(found[i].getBoundingClientRect())) return true;
  }
  return false;
}

function waitForQuiet() {
  clearTimeout(quietTimer);
  var hasMain = document.querySelector('[role="main"]');
  quietTimer = setTimeout(function () {
    if (placeholderOnScreen() || (!hasMain && document.readyState === 'loading')) waitForQuiet();
    else reveal();
  }, !hasMain ? QUIET_NO_MAIN_MS : /^\/groups\/./.test(location.pathname) ? QUIET_GROUP_MS : QUIET_MS);
}

function reveal() {
  clearTimeout(quietTimer);
  clearTimeout(maxTimer);
  changes.disconnect();
  ready = true;
  root.setAttribute(READY, '');
}

function cover() {
  clearTimeout(maxTimer);
  ready = false;
  root.removeAttribute(READY);
  changes.observe(root, { childList: true, subtree: true });
  waitForQuiet();
  maxTimer = setTimeout(reveal, MAX_MS);
}

function isNewPage(from, to) {
  if (from === to || OVER_THE_PAGE.test(from) || OVER_THE_PAGE.test(to)) return false;
  var section = from.split('/')[1];
  return !(section === to.split('/')[1] && ONE_PAGE_SECTIONS.indexOf(section) !== -1);
}

kwHab.onNavigate(function (loc) {
  var from = path;
  path = loc.pathname;
  if (!isNewPage(from, path)) return;
  var bar = document.querySelector('[role="navigation"][aria-label="Facebook"]');
  if (bar) root.style.setProperty('--kw-cover-top', bar.getBoundingClientRect().bottom + 'px');
  cover();
});

// Facebook sometimes rewrites <html>'s attributes.
new MutationObserver(function () {
  if (ready && !root.hasAttribute(READY)) root.setAttribute(READY, '');
}).observe(root, { attributes: true, attributeFilter: [READY] });

cover();
