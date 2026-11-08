// Speech to text for every text box. The user presses "Speak", talks, presses
// "Stop", and what they said is typed into the box. Transcription is done by
// ElevenLabs through the Dart side (lib/speech/), via the `kwSpeechToText`
// handler, so the API key never enters this page.
//
// - Messenger's composer: a "Speak to type" button left of the emoji button
//   ("Send a voice clip" stays, for sending a recording instead).
// - Any other text box (posts, comments, search): the same button appears
//   next to it while it has focus.

var HANDLER = 'kwSpeechToText';
var MAX_RECORDING_MS = 60000;
var TEXTBOX = '[contenteditable="true"][role="textbox"], textarea, ' +
  'input[type="text"], input[type="search"], input:not([type])';
var EMOJI = '[role="button"][aria-label="Choose an emoji"]';

var LABELS = {
  idle: 'Speak to type',
  listening: 'Stop',
  working: 'Writing…',
};
var ERRORS = {
  not_configured: "Speaking isn't set up yet",
  unauthorized: "Speaking isn't set up yet",
  no_mic: 'Allow the microphone, then try again',
  empty: "Didn't catch that. Try again.",
  too_long: 'That was too long. Try a shorter message.',
};
var DEFAULT_ERROR = "Couldn't hear that. Try again.";

// The one recording in progress: { button, target, recorder, stream, timer }.
var session = null;

function setState(button, state, message) {
  button.setAttribute('data-state', state);
  var label = message || LABELS[state];
  button.querySelector('.kw-speak__label').textContent = label;
  var spoken = state === 'idle' ? 'Speak instead of typing' : label;
  button.setAttribute('aria-label', spoken);
  button.setAttribute('title', spoken);
}

function showError(button, code) {
  setState(button, 'error', ERRORS[code] || DEFAULT_ERROR);
  setTimeout(function () {
    if (button.getAttribute('data-state') === 'error') setState(button, 'idle');
  }, 4000);
}

function recordingType() {
  var types = ['audio/webm;codecs=opus', 'audio/webm', 'audio/mp4', 'audio/ogg;codecs=opus'];
  for (var i = 0; i < types.length; i++) {
    if (window.MediaRecorder && MediaRecorder.isTypeSupported(types[i])) return types[i];
  }
  return '';
}

function toBase64(blob) {
  return new Promise(function (resolve, reject) {
    var reader = new FileReader();
    reader.onload = function () { resolve(String(reader.result).split(',')[1] || ''); };
    reader.onerror = function () { reject(reader.error); };
    reader.readAsDataURL(blob);
  });
}

function start(button, target) {
  if (session) return;
  if (!navigator.mediaDevices || !window.MediaRecorder) {
    showError(button, 'no_mic');
    return;
  }
  session = { button: button, target: target };
  var mine = session;
  setState(button, 'listening');
  navigator.mediaDevices.getUserMedia({ audio: true }).then(function (stream) {
    if (session !== mine) { // cancelled while asking for the microphone
      stream.getTracks().forEach(function (t) { t.stop(); });
      return;
    }
    var type = recordingType();
    var recorder = new MediaRecorder(stream, type ? { mimeType: type } : undefined);
    var chunks = [];
    recorder.ondataavailable = function (e) { if (e.data && e.data.size) chunks.push(e.data); };
    recorder.onstop = function () {
      stream.getTracks().forEach(function (t) { t.stop(); });
      transcribe(mine, new Blob(chunks, { type: recorder.mimeType || type || 'audio/webm' }));
    };
    mine.stream = stream;
    mine.recorder = recorder;
    mine.timer = setTimeout(function () { stop(mine); }, MAX_RECORDING_MS);
    recorder.start();
  }).catch(function (e) {
    kwHab.log('speech-to-text', 'no microphone', e && e.name);
    if (session === mine) session = null;
    showError(button, 'no_mic');
  });
}

function stop(mine) {
  if (!mine || session !== mine) return;
  clearTimeout(mine.timer);
  if (mine.recorder && mine.recorder.state !== 'inactive') {
    setState(mine.button, 'working');
    mine.recorder.stop(); // -> onstop -> transcribe
  }
}

function transcribe(mine, blob) {
  var bridge = window.flutter_inappwebview;
  if (!bridge || !bridge.callHandler) {
    finish(mine, null, 'no_bridge');
    return;
  }
  toBase64(blob).then(function (audio) {
    return bridge.callHandler(HANDLER, audio, blob.type);
  }).then(function (result) {
    if (!result || !result.ok) return finish(mine, null, result && result.error);
    var text = (result.text || '').trim();
    finish(mine, text, text ? null : 'empty');
  }).catch(function (e) {
    kwHab.log('speech-to-text', 'failed', e);
    finish(mine, null, 'failed');
  });
}

function finish(mine, text, error) {
  if (session === mine) session = null;
  if (error) {
    showError(mine.button, error);
    return;
  }
  setState(mine.button, 'idle');
  insertText(mine.target, text);
}

// Types [text] at the caret, as if the user had typed it, so Facebook's own
// editors (and React inputs) see a normal edit.
function insertText(target, text) {
  if (!target || !target.isConnected) return;
  target.focus();
  var before = textBeforeCaret(target);
  if (before && !/\s$/.test(before)) text = ' ' + text;
  if (document.execCommand('insertText', false, text)) return;
  if ('value' in target) { // fallback for plain inputs
    var setter = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(target), 'value').set;
    setter.call(target, target.value + text);
    target.dispatchEvent(new Event('input', { bubbles: true }));
  }
}

function textBeforeCaret(target) {
  if ('value' in target && typeof target.selectionStart === 'number') {
    return target.value.slice(0, target.selectionStart);
  }
  var selection = window.getSelection();
  if (!selection.rangeCount || !target.contains(selection.anchorNode)) {
    // No caret in the box: put it at the end.
    var end = document.createRange();
    end.selectNodeContents(target);
    end.collapse(false);
    selection.removeAllRanges();
    selection.addRange(end);
  }
  var range = selection.getRangeAt(0).cloneRange();
  range.setStart(target, 0);
  return range.toString();
}

function makeButton(getTarget) {
  var button = kwHab.fragment('speech-to-text').querySelector('.kw-speak');
  // Keep the text box focused (and its caret where it was).
  button.addEventListener('mousedown', function (e) { e.preventDefault(); });
  button.addEventListener('click', function (event) {
    event.preventDefault();
    event.stopPropagation();
    if (session && session.button === button) {
      stop(session);
      return;
    }
    if (session || button.getAttribute('data-state') === 'working') return;
    var target = getTarget();
    if (target) start(button, target);
  });
  return button;
}

// ---- Messenger's composer: a labelled button left of the emoji button ---------

function composerBox(from) {
  for (var node = from; node && node !== document.body; node = node.parentElement) {
    var box = node.querySelector('[contenteditable="true"][role="textbox"]');
    if (box) return box;
  }
  return null;
}

kwHab.onElement(EMOJI, function (emoji) {
  var box = composerBox(emoji);
  if (!box) return;
  // The emoji button's slot: its ancestor that sits beside the text box.
  var slot = emoji;
  while (slot.parentElement && !slot.parentElement.contains(box)) slot = slot.parentElement;
  if (!slot.parentElement || slot === document.body) return;
  // Messenger rebuilds the emoji button (e.g. after a message is sent) next to
  // ours: keep our button.
  var previous = slot.previousElementSibling;
  var button = previous && previous.classList.contains('kw-speak--composer') ? previous : null;
  if (!button) {
    button = makeButton(function () { return composerBox(button); });
    button.classList.add('kw-speak--composer');
    slot.parentElement.insertBefore(button, slot);
  }
  // Match the chat's theme colour, which Messenger sets on its toolbar icons
  // (the voice clip one is a plain icon whose colour is that theme colour).
  var color = themeColor(slot);
  if (color) button.style.setProperty('--kw-speak-icon', color);
});

function themeColor(from) {
  for (var node = from; node && node !== document.body; node = node.parentElement) {
    var icon = node.querySelector('[role="button"][aria-label="Send a voice clip"] svg');
    if (icon) return getComputedStyle(icon).color;
  }
  return null;
}

// ---- Every other text box: a "Speak" button while it has focus ---------------

var floating = null; // the shared button, created on first use
var floatingTarget = null;

// Messenger composers already have their own button.
function hasComposerButton(box) {
  var buttons = document.querySelectorAll('.kw-speak--composer');
  for (var i = 0; i < buttons.length; i++) {
    if (composerBox(buttons[i]) === box) return true;
  }
  return false;
}

function placeFloating() {
  if (!floating || !floatingTarget) return;
  var box = floatingTarget.getBoundingClientRect();
  if (!box.width || !box.height) return hideFloating();
  var size = floating.getBoundingClientRect();
  // Just below the box's right end; above it if there's no room below.
  var top = box.bottom + 6;
  if (top + size.height > window.innerHeight - 8) top = box.top - size.height - 6;
  var left = Math.min(box.right - size.width, window.innerWidth - size.width - 8);
  floating.style.top = Math.max(8, top) + 'px';
  floating.style.left = Math.max(8, left) + 'px';
}

function showFloating(box) {
  if (!floating) {
    floating = makeButton(function () { return floatingTarget; });
    floating.classList.add('kw-speak--floating');
    document.body.appendChild(floating);
    window.addEventListener('scroll', placeFloating, true);
    window.addEventListener('resize', placeFloating);
  }
  if (!floating.isConnected) document.body.appendChild(floating);
  floatingTarget = box;
  floating.hidden = false;
  placeFloating();
}

function hideFloating() {
  // Stay put while listening or writing: the user still needs "Stop".
  if (!floating || (session && session.button === floating) ||
      floating.getAttribute('data-state') === 'working') return;
  floating.hidden = true;
  floatingTarget = null;
}

document.addEventListener('focusin', function (e) {
  var box = e.target;
  if (!box.matches || !box.matches(TEXTBOX) || box.closest('.kw-speak')) return;
  if (hasComposerButton(box)) return hideFloating();
  if (session && session.button === floating) return;
  showFloating(box);
}, true);

document.addEventListener('focusout', function () {
  // Wait for focus to land somewhere: moving between boxes shows it again.
  setTimeout(function () {
    var active = document.activeElement;
    if (active && active.matches && active.matches(TEXTBOX)) return;
    hideFloating();
  }, 150);
}, true);

// Leaving the page stops listening without typing anything.
kwHab.onNavigate(function () {
  if (!session) return;
  var mine = session;
  session = null;
  clearTimeout(mine.timer);
  if (mine.recorder && mine.recorder.state !== 'inactive') {
    mine.recorder.onstop = null;
    mine.recorder.stop();
  }
  if (mine.stream) mine.stream.getTracks().forEach(function (t) { t.stop(); });
  setState(mine.button, 'idle');
  hideFloating();
});
