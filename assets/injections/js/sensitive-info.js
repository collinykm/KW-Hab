// Sensitive info warning. Before a message, comment, post or any other text box
// is sent (Enter, or a Send / Post button), the text is checked for things
// that look private: a credit or debit card number, a SIN, a password or PIN,
// bank or health card numbers. If any are found, a popup asks "It looks like
// you're entering some sensitive info. Do you want to proceed?":
//   - "No, go back" leaves the text in the box so it can be changed;
//   - "Yes, proceed" sends it as normal.
// Once the user says yes for a value in a box, they aren't asked again about
// that value until the box is emptied (e.g. the message was sent).
//
// The checks are hard-coded patterns (see find() below), run only on the page:
// nothing is sent anywhere to check it.

// ---- What counts as sensitive ----------------------------------------------

var KINDS = {
  card: 'A credit or debit card number',
  sin: 'A Social Insurance Number (SIN)',
  ssn: 'A Social Security Number',
  password: 'A password or PIN',
  bank: 'A bank account number',
  security: 'A card security code',
  health: 'A health card number',
  id: "A passport or driver's licence number",
};

// A keyword, then (within a few words) a number with at least `digits` digits.
var KEYWORD_NUMBERS = [
  { kind: 'sin', digits: 6, re: /(?:\bS\.?I\.?N\b|social\s+insurance)/g },
  { kind: 'ssn', digits: 6, re: /(?:\bSSN\b|social\s+security)/gi },
  { kind: 'card', digits: 8, re: /\b(?:(?:credit|debit)\s+card|card\s*(?:number|no\.?|#)|visa|master\s?card|amex)/gi },
  { kind: 'security', digits: 3, re: /\b(?:cvv2?|cvc|security\s+code)\b/gi },
  { kind: 'bank', digits: 5, re: /\b(?:bank\s+account|account\s*(?:number|no\.?|#)|chequing|checking|savings\s+account|transit\s*(?:number|no\.?|#)|institution\s*(?:number|no\.?|#)|routing\s*(?:number|no\.?|#))/gi },
  { kind: 'health', digits: 8, re: /\b(?:health\s+card|OHIP)\b/gi },
  { kind: 'id', digits: 6, re: /\b(?:passport|driver'?s?\s+licen[cs]e|licen[cs]e\s*(?:number|no\.?|#))/gi },
];
// The few characters after a keyword that may come before its number
// ("is", ":", "#"), then the number.
var NUMBER_AFTER = /^[^\n\d]{0,30}?(\d(?:[ \-.]?\d)*)/;

// "password is ...", "pin: 1234".
var PASSWORD = /\b(?:password|passcode|passwd|pass\s+word)\s*(?:is|was|=|:|-)\s*:?\s*(\S{3,})/gi;
var PIN = /\b(?:PIN|pin\s+(?:number|code))\s*(?:is|was|=|:|-|#)?\s*:?\s*(\d{4,8})\b/gi;
// Words after "password is" that describe it rather than being it.
var NOT_A_PASSWORD = /^(?:wrong|incorrect|correct|right|expired|changed|different|working|invalid|forgotten|lost|required|reset|hacked|weak|strong|same|too|not|the|my|your|his|her|their|our|a|an|so|very|really|still|now|case|long|short|new|old|easy|hard|good|bad|secret|private|safe|in|on|for|what|why|how)\W*$/i;

// Runs of digits split by single spaces, dashes or dots: "4111 1111-1111 1111".
var DIGIT_RUN = /\d+(?:[ \-.]\d+)*/g;

function luhn(digits) {
  var sum = 0;
  for (var i = 0; i < digits.length; i++) {
    var d = +digits[digits.length - 1 - i];
    if (i % 2 === 1) {
      d *= 2;
      if (d > 9) d -= 9;
    }
    sum += d;
  }
  return sum % 10 === 0;
}

// Numbers that look like a card, SIN or SSN on their own, without a keyword.
function findNumbers(text, add) {
  var run;
  DIGIT_RUN.lastIndex = 0;
  while ((run = DIGIT_RUN.exec(text))) {
    var groups = run[0].split(/[ \-.]/);
    var seps = run[0].replace(/\d/g, '');
    // Every stretch of whole groups, so a card next to an expiry date
    // ("4111 1111 1111 1111 12 25") is still found.
    for (var from = 0; from < groups.length; from++) {
      var digits = '';
      for (var to = from; to < groups.length; to++) {
        digits += groups[to];
        var count = to - from + 1;
        if (digits.length >= 13 && digits.length <= 19 && luhn(digits) && !/^(\d)\1+$/.test(digits)) {
          add('card', digits);
        }
        if (digits.length === 9 && /^[0-79]/.test(digits) && luhn(digits) &&
            (count === 1 || (count === 3 && groups[from].length === 3 && groups[from + 1].length === 3))) {
          add('sin', digits);
        }
        if (count === 3 && groups[from].length === 3 && groups[from + 1].length === 2 &&
            groups[to].length === 4 && seps.charAt(from) === '-' &&
            !/^(000|666|9)/.test(groups[from])) {
          add('ssn', digits);
        }
        if (digits.length > 19) break;
      }
    }
  }
}

// Returns [{ kind, value }] for everything sensitive-looking in text, each
// value at most once.
function find(text) {
  var found = [];
  var seen = {};
  function add(kind, value) {
    var key = kind + ':' + value;
    if (seen[key]) return;
    seen[key] = true;
    found.push({ kind: kind, value: value });
  }
  if (!text || !/\S/.test(text)) return found;

  findNumbers(text, add);

  KEYWORD_NUMBERS.forEach(function (rule) {
    var m;
    rule.re.lastIndex = 0;
    while ((m = rule.re.exec(text))) {
      var n = NUMBER_AFTER.exec(text.slice(m.index + m[0].length));
      var digits = n && n[1].replace(/\D/g, '');
      if (digits && digits.length >= rule.digits) add(rule.kind, digits);
      if (m[0].length === 0) rule.re.lastIndex++;
    }
  });

  var p;
  PASSWORD.lastIndex = 0;
  while ((p = PASSWORD.exec(text))) {
    if (!NOT_A_PASSWORD.test(p[1])) add('password', p[1]);
  }
  PIN.lastIndex = 0;
  while ((p = PIN.exec(text))) add('password', p[1]);

  return found;
}

// ---- Text boxes and send buttons -------------------------------------------

var TEXTBOX = '[contenteditable="true"], [role="textbox"], textarea, ' +
  'input[type="text"], input[type="search"], input[type="email"], input[type="tel"], input:not([type])';
// Buttons that send what's in a nearby text box: Messenger's send button,
// a comment box's send button, and the Post / Share now buttons of the post
// and share dialogs.
var SEND_BUTTON = [
  '#focused-state-composer-submit',
  '[role="button"][aria-label="Press enter to send"]',
  '[role="button"][aria-label="Send"]',
  '[role="button"][aria-label="Post"]',
  '[role="button"][aria-label="Share now"]',
  'button[type="submit"]',
  'input[type="submit"]',
].join(', ');

function editableRoot(el) {
  if (!el || !el.closest) return null;
  var box = el.closest(TEXTBOX);
  if (!box || box.closest('.kw-sensitive')) return null;
  // The outermost contenteditable, not a paragraph inside it.
  while (box.parentElement && box.parentElement.closest('[contenteditable="true"]')) {
    box = box.parentElement.closest('[contenteditable="true"]');
  }
  return box;
}

function textOf(box) {
  return 'value' in box && box.tagName !== 'DIV' ? box.value || '' : box.innerText || '';
}

// The text boxes a send button sends from: the ones in its form or dialog, or
// else the first ones found climbing up from it.
function boxesFor(button) {
  var scope = button.closest('form') || button.closest('[role="dialog"]');
  for (var node = button.parentElement, depth = 0; !scope && node && depth < 8; node = node.parentElement, depth++) {
    if (node.querySelector(TEXTBOX)) scope = node;
  }
  if (!scope) return [];
  var boxes = [];
  scope.querySelectorAll(TEXTBOX).forEach(function (el) {
    var box = editableRoot(el);
    if (box && boxes.indexOf(box) < 0) boxes.push(box);
  });
  return boxes;
}

// Values the user said yes to, per text box.
var approved = new WeakMap();

function unapproved(boxes) {
  var result = [];
  boxes.forEach(function (box) {
    var ok = approved.get(box);
    find(textOf(box)).forEach(function (item) {
      if (!ok || !ok.has(item.kind + ':' + item.value)) result.push({ box: box, item: item });
    });
  });
  return result;
}

function approve(found) {
  found.forEach(function (f) {
    var ok = approved.get(f.box);
    if (!ok) approved.set(f.box, (ok = new Set()));
    ok.add(f.item.kind + ':' + f.item.value);
  });
}

// An emptied box (the message went) asks again next time.
document.addEventListener('beforeinput', function (e) {
  var box = editableRoot(e.target);
  if (box && !/\S/.test(textOf(box))) approved.delete(box);
}, true);

// ---- The popup --------------------------------------------------------------

var dialog = null;
var pending = null; // { found, proceed, box }

function buildDialog() {
  dialog = kwHab.fragment('sensitive-info').querySelector('.kw-sensitive');
  var no = dialog.querySelector('.kw-sensitive__button--no');
  var yes = dialog.querySelector('.kw-sensitive__button--yes');
  no.addEventListener('click', function () { close(false); });
  yes.addEventListener('click', function () { close(true); });
  // Keep keys from reaching Facebook's shortcuts while the popup is open.
  dialog.addEventListener('keydown', function (e) {
    e.stopPropagation();
    if (e.key === 'Escape') {
      e.preventDefault();
      close(false);
    } else if (e.key === 'Tab') {
      e.preventDefault();
      (document.activeElement === no ? yes : no).focus();
    }
  });
  // Clicking the dark area around the box is "No".
  dialog.addEventListener('click', function (e) {
    if (e.target === dialog) close(false);
  });
}

function open(found, box, proceed) {
  if (!dialog) buildDialog();
  if (pending) return;
  pending = { found: found, box: box, proceed: proceed };
  var list = dialog.querySelector('.kw-sensitive__kinds');
  list.textContent = '';
  var shown = {};
  found.forEach(function (f) {
    if (shown[f.item.kind]) return;
    shown[f.item.kind] = true;
    var li = document.createElement('li');
    li.textContent = KINDS[f.item.kind];
    list.appendChild(li);
  });
  if (!dialog.isConnected) document.body.appendChild(dialog);
  dialog.hidden = false;
  dialog.querySelector('.kw-sensitive__button--no').focus();
  kwHab.log('sensitive-info', 'asked about', Object.keys(shown).join(', '));
}

function close(yes) {
  if (!pending) return;
  var mine = pending;
  pending = null;
  dialog.hidden = true;
  if (mine.box && mine.box.isConnected) mine.box.focus();
  if (!yes) return;
  approve(mine.found);
  mine.proceed();
}

// Facebook can rebuild the page around the popup; never leave it stuck open.
kwHab.onNavigate(function () { close(false); });

// ---- Catching a send ---------------------------------------------------------

// Pressing Enter in a text box (sends a message or comment; in a post it's a
// new line, which is asked about once and then allowed).
window.addEventListener('keydown', function (e) {
  if (e.key !== 'Enter' || e.shiftKey || e.isComposing || e.keyCode === 229) return;
  var box = editableRoot(e.target);
  if (!box) return;
  var found = unapproved([box]);
  if (!found.length) return;
  e.preventDefault();
  e.stopImmediatePropagation();
  open(found, box, function () {
    var send = sendButtonFor(box);
    if (send) {
      send.click();
      return;
    }
    var again = new KeyboardEvent('keydown', {
      key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true,
    });
    box.dispatchEvent(again);
    if (box.tagName === 'INPUT' && box.form && !again.defaultPrevented) box.form.requestSubmit();
  });
}, true);

// Messenger's and comment boxes' send buttons, when Enter's "yes" can use one
// (more reliable than replaying Enter into Facebook's editor).
function sendButtonFor(box) {
  var form = box.closest('form');
  var submit = form && form.querySelector('#focused-state-composer-submit [role="button"], #focused-state-composer-submit');
  if (submit) return submit;
  for (var node = box.parentElement, depth = 0; node && depth < 8; node = node.parentElement, depth++) {
    var button = node.querySelector('[role="button"][aria-label="Press enter to send"]');
    if (button) return button;
  }
  return null;
}

// Clicking a send button.
window.addEventListener('click', function (e) {
  if (!e.target.closest) return;
  var button = e.target.closest(SEND_BUTTON);
  if (!button || button.closest('.kw-sensitive')) return;
  var found = unapproved(boxesFor(button));
  if (!found.length) return;
  e.preventDefault();
  e.stopImmediatePropagation();
  open(found, found[0].box, function () { button.click(); });
}, true);

// Pressing Enter on a focused send button is a click too, but some of
// Facebook's buttons act on the keydown itself.
window.addEventListener('keydown', function (e) {
  if ((e.key !== 'Enter' && e.key !== ' ') || !e.target.closest) return;
  var button = e.target.closest(SEND_BUTTON);
  if (!button || button.closest('.kw-sensitive') || editableRoot(e.target)) return;
  var found = unapproved(boxesFor(button));
  if (!found.length) return;
  e.preventDefault();
  e.stopImmediatePropagation();
  open(found, found[0].box, function () { button.click(); });
}, true);
