// Top bar (div[role="banner"]). See css/top-bar.css for what is hidden.
//
// Middle: adds a Messages tab after Reels, built by cloning Facebook's Reels
// tab so it looks the same. It opens full-screen Messenger (/messages/).
//
// Profile menu: keeps the profile name link, a "Getting started" item that
// opens onboarding, and Log out. Everything else is hidden.

var MESSAGES_PATH = '/messages/';
// TODO: replace with the real onboarding screen once it exists.
var ONBOARDING_URL = '#kw-onboarding';

var MAIN_NAV = 'div[role="navigation"][aria-label="Facebook"]';
var PROFILE_MENU = 'div[role="dialog"][aria-label="Your profile"]';
var HIDDEN = 'data-kw-top-bar-hidden';

function icon(name) {
  return kwHab.fragment('top-bar').querySelector('[data-kw-icon="' + name + '"]');
}

// Swap an <svg>'s drawing for one of our icons, keeping Facebook's classes and
// colour variables on the element itself.
function setIcon(svg, name) {
  var src = icon(name);
  svg.setAttribute('viewBox', src.getAttribute('viewBox'));
  svg.innerHTML = src.innerHTML;
}

// ---- Messages tab ---------------------------------------------------------

function updateMessagesTab() {
  var active = location.pathname.indexOf(MESSAGES_PATH) === 0;
  document.querySelectorAll('.kw-top-bar-messages').forEach(function (item) {
    var link = item.querySelector('a');
    if (active) {
      item.setAttribute('data-kw-active', '');
      link.setAttribute('aria-current', 'page');
    } else {
      item.removeAttribute('data-kw-active');
      link.removeAttribute('aria-current');
    }
  });
}

kwHab.onElement(MAIN_NAV + ' a[aria-label="Reels"]', function (reels) {
  var tab = reels.closest('li');
  if (!tab || tab.parentElement.querySelector('.kw-top-bar-messages')) return;

  var item = tab.cloneNode(true);
  item.classList.add('kw-top-bar-messages');
  var link = item.querySelector('a');
  link.setAttribute('aria-label', 'Messages');
  link.setAttribute('title', 'Messages');
  link.setAttribute('href', MESSAGES_PATH);
  link.removeAttribute('aria-current');
  if (link.previousElementSibling) link.previousElementSibling.classList.add('kw-top-bar-indicator');
  var svg = link.querySelector('svg');
  if (svg) setIcon(svg, 'messages');

  tab.after(item);
  updateMessagesTab();
});

kwHab.onNavigate(updateMessagesTab);

// ---- Profile menu ---------------------------------------------------------

function openOnboarding() {
  location.href = ONBOARDING_URL;
}

function makeOnboardingItem(logOut) {
  var item = logOut.cloneNode(true);
  item.classList.add('kw-top-bar-onboarding');
  item.removeAttribute(HIDDEN);

  var label = item.querySelector('span[dir="auto"]') || item.querySelector('span');
  if (label) label.textContent = 'Settings';

  //Text label for the "settings"/"onboarding" button

  var sprite = item.querySelector('i');
  if (sprite) sprite.replaceWith(icon('onboarding'));

  var button = item.querySelector('[role="button"]') || item;
  button.setAttribute('role', 'link');
  button.addEventListener('click', function (e) {
    e.preventDefault();
    e.stopPropagation();
    openOnboarding();
  });
  button.addEventListener('keydown', function (e) {
    if (e.key !== 'Enter' && e.key !== ' ') return;
    e.preventDefault();
    openOnboarding();
  });
  return item;
}

// Hides every option except Log out, and puts "Getting started" above it.
// Safe to run repeatedly; Facebook may add items after the list appears.
function trimProfileOptions(list) {
  var items = Array.prototype.filter.call(list.querySelectorAll('div[role="listitem"]'), function (i) {
    return !i.classList.contains('kw-top-bar-onboarding');
  });
  if (!items.length) return;

  var logOut = items.find(function (i) {
    return /^log ?out$/i.test(i.textContent.trim());
  }) || items[items.length - 1]; // Log out is last; fallback for other languages.

  items.forEach(function (i) {
    if (i === logOut) i.removeAttribute(HIDDEN);
    else i.setAttribute(HIDDEN, '');
  });

  var onboarding = list.querySelector('.kw-top-bar-onboarding');
  if (!onboarding) onboarding = makeOnboardingItem(logOut);
  if (onboarding.nextElementSibling !== logOut) logOut.before(onboarding);
}

kwHab.onElement(PROFILE_MENU + ' div[role="listitem"]', function (item) {
  if (item.classList.contains('kw-top-bar-onboarding')) return;
  var list = item.closest('div[role="list"]');
  if (list) trimProfileOptions(list);
});

// The profile card shows the user's name (kept) above "See all profiles" and a
// divider (hidden).
kwHab.onElement(PROFILE_MENU + ' [aria-label="See all profiles"]', function (button) {
  var dialog = button.closest(PROFILE_MENU);
  var row = button;
  while (row.parentElement && row.parentElement !== dialog &&
         !row.parentElement.querySelector('a[href="/me/"]')) {
    row = row.parentElement;
  }
  var card = row.parentElement;
  if (!card || card === dialog) {
    button.setAttribute(HIDDEN, '');
    return;
  }
  var nameLink = card.querySelector('a[href="/me/"]');
  Array.prototype.forEach.call(card.children, function (child) {
    if (!child.contains(nameLink)) child.setAttribute(HIDDEN, '');
  });
});
