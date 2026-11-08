// The "Create post" dialog. css/post-dialog.css hides everything that has an
// aria-label (AI label, Check in, Life update, the "More" button, background
// options, list-building audience choices, Pages and strangers in Tag people)
// before it paints. This file handles what CSS can't:
//
//   - The "Add to your post" list (opened from the row's label) has text-only
//     items. Check in, Life update, GIF, Live video and Raise money are hidden
//     there, leaving Photo/video, Tag people and Feeling/activity.
//   - Close Friends in Post audience is a text-only row.
//   - Hidden buttons' wrappers, so no gaps are left.
//
// Each hidden item is logged (kwHab:post-dialog).

var HIDDEN = 'data-kw-post-dialog-hidden';
var COMPOSER = '[role="dialog"]:has([aria-label="Close composer dialog"])';
var ROW_HIDDEN = ['Check in', 'Life update', 'More post options', 'Show background options'];
var LIST_HIDDEN = /^(Check in|Life update|GIF|Live video|Raise money)$/i;

function inComposer(el) {
  return !!el.closest(COMPOSER);
}

// Climb from el through wrappers that hold nothing else, stopping below the
// first ancestor with other children (the row or list). That top wrapper is
// the item's slot.
function slotOf(el) {
  var slot = el;
  while (slot.parentElement && slot.parentElement.children.length === 1) {
    slot = slot.parentElement;
  }
  return slot;
}

function hide(el, why) {
  var slot = slotOf(el);
  if (slot.hasAttribute(HIDDEN)) return;
  slot.setAttribute(HIDDEN, '');
  kwHab.log('post-dialog', 'hid', why);
}

function textOf(el) {
  return (el.textContent || '').trim();
}

// --- The dialog's own buttons ---------------------------------------------

ROW_HIDDEN.forEach(function (label) {
  kwHab.onElement('[role="button"][aria-label="' + label + '"]', function (button) {
    if (inComposer(button)) hide(button, label + ' (row)');
  });
});

// --- The "Add to your post" list ------------------------------------------
// Only the screen's header is the role="dialog" labelled "Add to your post";
// the items are in a sibling. So the screen is the header's parent.

var LIST_HEADER = '[role="dialog"][aria-label="Add to your post"]';
var LIST_SCREEN = 'div:has(> ' + LIST_HEADER + ')';

kwHab.onElement('[role="button"]', function (item) {
  if (item.closest(LIST_SCREEN) && inComposer(item)) checkListItem(item);
});

// In case the header mounts after the items.
kwHab.onElement(LIST_HEADER, function (header) {
  if (!header.parentElement || !inComposer(header)) return;
  header.parentElement.querySelectorAll('[role="button"]').forEach(checkListItem);
});

function checkListItem(item) {
  if (item.closest(LIST_HEADER)) return;
  var label = textOf(item);
  if (LIST_HIDDEN.test(label)) hide(item, label + ' (list)');
}

// --- Post audience --------------------------------------------------------

kwHab.onElement('[role="radiogroup"][aria-label="Select audience"] label', function (option) {
  var name = option.querySelector('span');
  if (!name || textOf(name) !== 'Close Friends') return;
  var input = option.querySelector('input[type="radio"]');
  if (input && (input.checked || input.getAttribute('aria-checked') === 'true')) return;
  hide(option, 'Close Friends (audience)');
});
