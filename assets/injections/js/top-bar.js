// Top bar (div[role="banner"]). See css/top-bar.css for what is hidden.
//
// Middle: adds a Messages tab after Reels, built by cloning Facebook's Reels
// tab so it looks the same. It opens full-screen Messenger (/messages/).
// Every tab, and the profile button, gets a text label under its icon.
//
// Profile menu: keeps the profile name link (with a "View my profile" hint),
// a "Settings" item that opens KW Hab's own settings screen (the native
// onboarding/settings screen, via the kwOpenSettings bridge; not Facebook's
// settings), and Log out. Everything else is hidden.

var MESSAGES_PATH = '/messages/';
// Dart handler that shows the settings screen (lib/settings/open_settings_bridge.dart).
var SETTINGS_HANDLER = 'kwOpenSettings';

var MAIN_NAV = 'div[role="navigation"][aria-label="Facebook"]';
var PROFILE_BUTTON = 'div[role="navigation"][aria-label="Account Controls and Settings"] [role="button"][aria-label="Account, your profile"]';
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

// Adds (or updates) a text label under an icon. Labels are aria-hidden: the
// element they sit in already has an aria-label with the same meaning.
function setLabel(parent, text) {
  var label = parent.querySelector(':scope > .kw-top-bar-label');
  if (!label) {
    label = document.createElement('span');
    label.className = 'kw-top-bar-label';
    label.setAttribute('aria-hidden', 'true');
    parent.appendChild(label);
  }
  label.textContent = text;
}

// ---- Middle tabs ----------------------------------------------------------

// "Friends, 3 new requests" -> "Friends".
kwHab.onElement(MAIN_NAV + ' a[role="link"][aria-label]', function (link) {
  setLabel(link, link.getAttribute('aria-label').split(',')[0]);
});

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
  link.setAttribute('href', MESSAGES_PATH);
  link.removeAttribute('aria-current');
  if (link.previousElementSibling) link.previousElementSibling.classList.add('kw-top-bar-indicator');
  var svg = link.querySelector('svg');
  if (svg) setIcon(svg, 'messages');
  setLabel(link, 'Messages');

  tab.after(item);
  updateMessagesTab();
});

kwHab.onNavigate(updateMessagesTab);

// ---- Profile button -------------------------------------------------------

kwHab.onElement(PROFILE_BUTTON, function (button) {
  setLabel(button, 'Account');
});

// ---- Profile menu ---------------------------------------------------------

function openSettings() {
  // Close Facebook's profile menu (its button toggles it) so it isn't still
  // open when the settings screen closes.
  var profileButton = document.querySelector(PROFILE_BUTTON);
  if (profileButton && document.querySelector(PROFILE_MENU)) profileButton.click();

  var bridge = window.flutter_inappwebview;
  if (!bridge || !bridge.callHandler) {
    kwHab.log('top-bar', 'settings bridge unavailable');
    return;
  }
  bridge.callHandler(SETTINGS_HANDLER).catch(function (e) {
    kwHab.log('top-bar', 'could not open settings', e);
  });
}

function makeSettingsItem(logOut) {
  var item = logOut.cloneNode(true);
  item.classList.add('kw-top-bar-settings');
  item.removeAttribute(HIDDEN);

  var label = item.querySelector('span[dir="auto"]') || item.querySelector('span');
  if (label) label.textContent = 'Settings';

  var sprite = item.querySelector('i');
  if (sprite) sprite.replaceWith(icon('settings'));

  var button = item.querySelector('[role="button"]') || item;
  button.setAttribute('role', 'link');
  button.addEventListener('click', function (e) {
    e.preventDefault();
    e.stopPropagation();
    openSettings();
  });
  button.addEventListener('keydown', function (e) {
    if (e.key !== 'Enter' && e.key !== ' ') return;
    e.preventDefault();

    openSettings();
  });
  return item;
}

// Hides every option except Log out, and puts "Settings" above it.
// Safe to run repeatedly; Facebook may add items after the list appears.
function trimProfileOptions(list) {
  var items = Array.prototype.filter.call(list.querySelectorAll('div[role="listitem"]'), function (i) {
    return !i.classList.contains('kw-top-bar-settings');
  });
  if (!items.length) return;

  var logOut = items.find(function (i) {
    return /^log ?out$/i.test(i.textContent.trim());
  }) || items[items.length - 1]; // Log out is last; fallback for other languages.

  items.forEach(function (i) {
    if (i === logOut) i.removeAttribute(HIDDEN);
    else i.setAttribute(HIDDEN, '');
  });

  var settings = list.querySelector('.kw-top-bar-settings');
  if (!settings) settings = makeSettingsItem(logOut);
  if (settings.nextElementSibling !== logOut) logOut.before(settings);
}

kwHab.onElement(PROFILE_MENU + ' div[role="listitem"]', function (item) {
  if (item.classList.contains('kw-top-bar-settings')) return;
  var list = item.closest('div[role="list"]');
  if (list) trimProfileOptions(list);
});

// "View my profile" under the user's name in the profile card.
kwHab.onElement(PROFILE_MENU + ' a[href="/me/"] span[dir="auto"]', function (name) {
  var hint = name.parentElement.querySelector('.kw-top-bar-profile-hint');
  if (hint) return;
  hint = document.createElement('span');
  hint.className = 'kw-top-bar-profile-hint';
  hint.textContent = 'View my profile';
  name.after(hint);
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
