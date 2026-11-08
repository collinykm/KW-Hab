// The message bar of a Messenger conversation. See css/chat-composer.css for
// what is hidden. This file
//   - renames "Send a voice clip" to "Voice message" and swaps its
//     microphone for a sound-wave icon (a dot with two arcs opening to the
//     right, like a Wi-Fi symbol turned on its side), the voice message
//     symbol many messaging apps use. Done both in the bar and in the + menu
//     shown while typing;
//   - renames "Attach a file up to 100 MB" to "Photo" in the same places;
//   - marks the kept buttons and their slots for the CSS to label and widen,
//     and the bar's row so the CSS can keep the text box off its right edge;
//     and hides the sticker and GIF slots so they leave no gap.

var BAR = '[aria-label="Thread composer"] [role="button"]';
var MENU = '[role="menu"][aria-label="More actions menu"] [role="menuitem"]';
var VOICE = '[aria-label="Send a voice clip"]';
var PHOTO = '[aria-label^="Attach a file"]';
var DROP = ['[aria-label="Choose a sticker"]', '[aria-label="Choose a GIF"]'];
var SVG_NS = 'http://www.w3.org/2000/svg';

function voiceIcon(svg) {
  while (svg.firstChild) svg.removeChild(svg.firstChild);
  svg.setAttribute('viewBox', '0 0 16 16');

  var dot = document.createElementNS(SVG_NS, 'circle');
  dot.setAttribute('cx', '3');
  dot.setAttribute('cy', '8');
  dot.setAttribute('r', '1.6');
  svg.appendChild(dot);

  // Arcs centred on the dot, from 45° above it to 45° below.
  [4.8, 9].forEach(function (r) {
    var d = r * Math.SQRT1_2;
    var x = (3 + d).toFixed(2);
    var arc = document.createElementNS(SVG_NS, 'path');
    arc.setAttribute('d', 'M' + x + ' ' + (8 - d).toFixed(2) + ' A' + r + ' ' + r + ' 0 0 1 ' + x + ' ' + (8 + d).toFixed(2));
    arc.setAttribute('fill', 'none');
    arc.setAttribute('stroke', 'currentColor');
    arc.setAttribute('stroke-width', '1.6');
    arc.setAttribute('stroke-linecap', 'round');
    svg.appendChild(arc);
  });
}

// The button's own slot in the bar: its highest ancestor holding nothing else.
function slotOf(button) {
  var slot = button;
  while (slot.parentElement && slot.parentElement.children.length === 1) slot = slot.parentElement;
  return slot;
}

// Menu items show their name as text. The text node is changed in place, not
// replaced, so React can still update it.
function renameText(item, from, to) {
  var walker = document.createTreeWalker(item, NodeFilter.SHOW_TEXT);
  for (var node = walker.nextNode(); node; node = walker.nextNode()) {
    if (node.nodeValue.trim() === from) node.nodeValue = to;
  }
}

// The row holding both the buttons and the text box.
function markRow(slot) {
  for (var el = slot.parentElement, depth = 0; el && depth < 4; el = el.parentElement, depth++) {
    if (el.querySelector('[role="textbox"]')) {
      el.setAttribute('data-kw-chat-composer-row', '');
      return;
    }
  }
}

kwHab.onElement(BAR + VOICE, function (button) {
  button.setAttribute('data-kw-chat-composer', 'voice');
  button.setAttribute('aria-label', 'Voice message');
  var slot = slotOf(button);
  slot.setAttribute('data-kw-chat-composer-slot', '');
  markRow(slot);
  var svg = button.querySelector('svg');
  if (svg) voiceIcon(svg);
});

kwHab.onElement(BAR + PHOTO, function (button) {
  button.setAttribute('data-kw-chat-composer', 'photo');
  button.setAttribute('aria-label', 'Photo');
  slotOf(button).setAttribute('data-kw-chat-composer-slot', '');
});

DROP.forEach(function (label) {
  kwHab.onElement(BAR + label, function (button) {
    slotOf(button).setAttribute('data-kw-chat-composer-hidden', '');
  });
});

kwHab.onElement(MENU + VOICE, function (item) {
  renameText(item, 'Send a voice clip', 'Voice message');
  item.setAttribute('aria-label', 'Voice message');
  var svg = item.querySelector('svg');
  if (svg) voiceIcon(svg);
});

kwHab.onElement(MENU + PHOTO, function (item) {
  renameText(item, item.getAttribute('aria-label'), 'Photo');
  item.setAttribute('aria-label', 'Photo');
});
