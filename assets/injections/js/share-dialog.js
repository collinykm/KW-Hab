// The Share dialog (from Share under posts and beside reels). It keeps its
// title and close button, "Send in Messenger" with its people, and "Share to"
// with only Copy link. The top half (posting the share to your own feed:
// audience, "Say something about this…", Share now), the "Report Bug" button
// and the other "Share to" options (Messenger, WhatsApp, Your story, Group,
// Friend's profile, …) are tagged, and css/share-dialog.css hides them.

var HIDDEN = 'data-kw-hidden';
var TAG = 'share-dialog';

// The first element in root whose text is exactly `text` (its innermost
// wrapper, since a span's parents often have the same text).
function byText(root, text) {
  var all = root.querySelectorAll('*');
  var found = null;
  for (var i = 0; i < all.length; i++) {
    if (all[i].textContent.trim() !== text) continue;
    if (found && !found.contains(all[i])) break;
    found = all[i];
  }
  return found;
}

// The largest box around el that holds none of keepers.
function outsideOf(el, keepers, root) {
  var box = el;
  for (;;) {
    var parent = box.parentElement;
    if (!parent || parent === root) return box;
    for (var i = 0; i < keepers.length; i++) {
      if (keepers[i] && parent.contains(keepers[i])) return box;
    }
    box = parent;
  }
}

function before(a, b) {
  return !!(a.compareDocumentPosition(b) & Node.DOCUMENT_POSITION_FOLLOWING) && !a.contains(b);
}

function hide(el) {
  el.setAttribute(HIDDEN, TAG);
}

// Facebook's "Report Bug" button, drawn beside the "Send in Messenger"
// heading (it may sit in a layer outside the dialog itself).
function hideReportBug(dialog) {
  var bug = dialog.querySelector('[aria-label="Report Bug"]') || document.querySelector('[aria-label="Report Bug"]');
  if (bug) hide(bug);
}

function trim(dialog) {
  var stale = dialog.querySelectorAll('[' + HIDDEN + '="' + TAG + '"]');
  for (var s = 0; s < stale.length; s++) stale[s].removeAttribute(HIDDEN);

  var messenger = byText(dialog, 'Send in Messenger');
  if (!messenger) return;
  var close = dialog.querySelector('[aria-label="Close"]');
  var title = byText(dialog, 'Share');

  // Top half: everything around the composer, up to the Messenger section.
  var topKeepers = [messenger, close, title];
  var composer = [byText(dialog, 'Share now'), dialog.querySelector('[role="textbox"], [contenteditable="true"]')];
  for (var c = 0; c < composer.length; c++) {
    if (composer[c] && before(composer[c], messenger)) hide(outsideOf(composer[c], topKeepers, dialog));
  }

  hideReportBug(dialog);

  // "Share to": every option but Copy link (and the carousel's arrows).
  var shareTo = byText(dialog, 'Share to');
  var copyText = byText(dialog, 'Copy link');
  if (!shareTo || !copyText) return;
  var copy = copyText.closest('[role="button"], [role="link"], a') || copyText;
  var keepers = [shareTo, copy, messenger];
  var options = dialog.querySelectorAll('[role="button"], [role="link"], a');
  for (var i = 0; i < options.length; i++) {
    var option = options[i];
    if (!before(shareTo, option) || copy.contains(option) || option.contains(copy)) continue;
    hide(outsideOf(option, keepers, dialog));
  }
}

// The dialog's sections render in stages; trim once things settle.
var pending = null;
function trimSoon() {
  if (pending) return;
  pending = setTimeout(function () {
    pending = null;
    document.querySelectorAll('[role="dialog"]').forEach(trim);
  }, 50);
}

kwHab.onElement('[role="dialog"] [role="button"]', trimSoon);
// Some parts (like Report Bug) may render outside the dialog, so look again
// once it has had time to fill in.
kwHab.onElement('[role="dialog"]', function () {
  setTimeout(trimSoon, 300);
  setTimeout(trimSoon, 1000);
});
