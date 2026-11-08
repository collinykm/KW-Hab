// The "What's on your mind, <name>?" composer at the top of the feed (and on
// your own profile). Its shortcut buttons are Live video, Photo/video and
// Feeling/activity. Only Photo/video is kept. Live video and Feeling/activity
// are still in the "Add to your post" row of the post dialog, so nothing is
// lost, the shortcuts just aren't on the first screen.
//
// css/composer.css hides the aria-labelled buttons before the page paints
// (no flash). Facebook has also shipped them as plain text, which CSS can't
// match, so this checks both and hides each button's wrapper too. Only
// buttons that share the composer with the "What's on your mind" prompt are
// hidden, never those inside the post dialog.

var HIDDEN = 'data-kw-composer-hidden';
var DROP = /^(Live video|Feeling\/activity)$/i;
var PROMPT = /^What's on your mind/i;
var MAX_DEPTH = 10;

function labelOf(el) {
  return (el.getAttribute('aria-label') || el.textContent || '').trim();
}

function hasPrompt(root) {
  var buttons = root.querySelectorAll('[role="button"]');
  for (var i = 0; i < buttons.length; i++) {
    if (PROMPT.test(labelOf(buttons[i]))) return true;
  }
  return false;
}

// The nearest ancestor that also holds the "What's on your mind" prompt.
function composerOf(button) {
  var el = button.parentElement;
  for (var depth = 0; el && depth < MAX_DEPTH; depth++, el = el.parentElement) {
    if (el.closest('[role="dialog"]')) return null;
    if (hasPrompt(el)) return el;
  }
  return null;
}

function hide(button, composer) {
  // Hide the button's own slot in the row, not just the button, so no empty
  // gap is left behind.
  var slot = button;
  while (slot.parentElement && slot.parentElement !== composer &&
         slot.parentElement.children.length === 1) {
    slot = slot.parentElement;
  }
  slot.setAttribute(HIDDEN, '');
}

function check(button) {
  if (!DROP.test(labelOf(button))) return;
  var composer = composerOf(button);
  if (composer) hide(button, composer);
}

// The prompt can render after the shortcuts, so when it appears, check the
// shortcut buttons around it too.
function checkAround(prompt) {
  var el = prompt.parentElement;
  for (var depth = 0; el && depth < MAX_DEPTH; depth++, el = el.parentElement) {
    el.querySelectorAll('[role="button"]').forEach(check);
  }
}

kwHab.onElement('[role="button"]', function (button) {
  if (PROMPT.test(labelOf(button))) checkAround(button);
  else check(button);
});
