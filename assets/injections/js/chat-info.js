// The "Conversation information" panel of a Messenger conversation. See
// css/chat-info.css for what is kept. This file
//   - closes the panel when a conversation opens (Facebook opens it by
//     default). The (i) button in the header still opens it;
//   - hides the Chat info, Customize chat and Media & files sections;
//   - keeps Privacy & support open, with its header and every item but Block
//     hidden, so Block shows at the bottom of the panel. It is Facebook's own
//     Block item, so its confirmation dialog still comes up;
//   - relabels Profile / Mute / Search as View profile / Mute chat / Search
//     in chat.
//
// Facebook re-renders the panel often, so it is swept every half second while
// a conversation is open.

var TOGGLE = '[role="main"] [role="button"][aria-label="Conversation information"]';
var HIDDEN = 'data-kw-chat-info-hidden';
var BLOCK = 'data-kw-chat-info-block';
var LABEL = 'data-kw-chat-info-label';
var DROP_SECTIONS = ['Chat info', 'Customize chat', 'Media & files', 'Media, files and links'];
var PRIVACY = 'Privacy & support';
var RELABEL = {
  'Profile': 'View profile',
  'Mute': 'Mute chat',
  'Unmute': 'Unmute chat',
  'Search': 'Search in chat',
};
var RELABEL_BUTTONS = '[role="main"] a[aria-label="Profile"], [role="main"] [role="button"][aria-label$="ute notifications"], [role="main"] [role="button"][aria-label="Search"]';

function inConversation() {
  return /^\/messages\/(e2ee\/)?t\//.test(location.pathname);
}

// ---- Closed by default ---------------------------------------------------

var closeBy = 0;

kwHab.onNavigate(function () {
  closeBy = inConversation() ? Date.now() + 8000 : 0;
});

function closeIfNew() {
  if (!closeBy) return;
  if (Date.now() > closeBy) { closeBy = 0; return; }
  var toggle = document.querySelector(TOGGLE);
  if (!toggle) return;
  closeBy = 0;
  if (toggle.getAttribute('aria-expanded') === 'true') {
    toggle.click();
    kwHab.log('chat-info', 'closed the conversation information panel');
  }
}

// ---- Sections --------------------------------------------------------------

function hide(el) {
  if (el && !el.hasAttribute(HIDDEN)) el.setAttribute(HIDDEN, '');
}

// A section is a [role="listitem"] holding its header button, followed by the
// region its contents open into (the button's aria-controls).
function sectionHeader(label) {
  return document.querySelector('[role="main"] [role="listitem"] [role="button"][aria-label="' + label + '"]');
}

function contentsOf(header) {
  var id = header.getAttribute('aria-controls');
  return id ? document.getElementById(id) : null;
}

function hideSection(label) {
  var header = sectionHeader(label);
  if (!header) return;
  hide(header.closest('[role="listitem"]'));
  hide(contentsOf(header));
}

function keepOnlyBlock() {
  var header = sectionHeader(PRIVACY);
  if (!header) return;
  hide(header.closest('[role="listitem"]'));
  if (header.getAttribute('aria-expanded') !== 'true') {
    header.click();
    return;
  }
  var contents = contentsOf(header);
  if (!contents) return;
  contents.querySelectorAll('[role="listitem"]').forEach(function (item) {
    if (item.textContent.trim() === 'Block') {
      if (!item.hasAttribute(BLOCK)) item.setAttribute(BLOCK, '');
    } else {
      hide(item);
    }
  });
}

// ---- Labels ----------------------------------------------------------------
// Each label sits beside its round button, not inside it: it is in the
// nearest ancestor of the button that has any text. Its text node is changed
// in place, not replaced, so Facebook can still update it (Mute -> Unmute)
// and the new text gets relabelled too.

function relabel(button) {
  var box = button;
  for (var depth = 0; box && depth < 4 && !box.textContent.trim(); depth++) box = box.parentElement;
  if (!box) return;
  var walker = document.createTreeWalker(box, NodeFilter.SHOW_TEXT);
  for (var node = walker.nextNode(); node; node = walker.nextNode()) {
    var label = RELABEL[node.nodeValue.trim()];
    if (!label) continue;
    node.nodeValue = label;
    node.parentElement.setAttribute(LABEL, '');
  }
}

// ---- Sweep ---------------------------------------------------------------

setInterval(function () {
  if (!inConversation()) return;
  closeIfNew();
  DROP_SECTIONS.forEach(hideSection);
  keepOnlyBlock();
  document.querySelectorAll(RELABEL_BUTTONS).forEach(relabel);
}, 500);
