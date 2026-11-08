// "Summarize post" buttons on feed posts and "Read aloud" buttons on chat
// messages. The user starts reading themselves; the button becomes "Stop
// reading" while audio plays. Speech comes from ElevenLabs through the Dart
// side (lib/speech/), via the `kwReadAloud` handler, so the API key never
// enters this page.
//
// Posts with a photo are summarized first: Cloudinary AI Vision looks at the
// photo together with the post's words (lib/cloudinary/, `kwSummarizePost`),
// so details that are only in the picture (a flyer's date and place, what is
// going on) are read out too. The summary is also shown under the button.
//
// Only while the user has "Read text aloud" on in Settings: the buttons are
// always added, but css/read-aloud.css hides them when it's off, so turning
// it on or off takes effect without a reload.

var SUMMARY_HANDLER = 'kwSummarizePost';
var LABELS = {
  idle: 'Read aloud',
  looking: 'Looking at the post…',
  loading: 'Getting audio…',
  playing: 'Stop reading',
};
var ERRORS = {
  not_configured: "Read aloud isn't set up yet",
  disabled: 'Read aloud is turned off in Settings',
  unauthorized: "Read aloud isn't set up yet",
  empty: 'Nothing to read here',
};
var DEFAULT_ERROR = "Couldn't read aloud. Try again.";

// The one thing being read right now: { button, audio, url } or { button } while loading.
var current = null;

function setState(button, state, message) {
  button.setAttribute('data-state', state);
  var idle = button.getAttribute('data-idle-label') || LABELS.idle;
  button.querySelector('.kw-read-aloud__label').textContent =
    message || (state === 'idle' ? idle : LABELS[state]);
  button.setAttribute('aria-pressed', state === 'playing' ? 'true' : 'false');
}

function stop() {
  if (!current) return;
  if (current.audio) current.audio.pause();
  if (current.url) URL.revokeObjectURL(current.url);
  if (current.button.isConnected) setState(current.button, 'idle');
  current = null;
}

function showError(button, code) {
  setState(button, 'error', ERRORS[code] || DEFAULT_ERROR);
  setTimeout(function () {
    if (button.getAttribute('data-state') === 'error') setState(button, 'idle');
  }, 4000);
}

function audioUrl(base64, mimeType) {
  var binary = atob(base64);
  var bytes = new Uint8Array(binary.length);
  for (var i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return URL.createObjectURL(new Blob([bytes], { type: mimeType }));
}

function enabled() {
  return kwHab.settings.readAloud === true;
}

// [getText] returns the text to read, or a promise of it.
function read(button, getText) {
  if (!enabled()) return;
  var wasThisButton = current && current.button === button;
  stop();
  if (wasThisButton) return; // the button said "Stop reading"

  var bridge = window.flutter_inappwebview;
  if (!bridge || !bridge.callHandler) {
    showError(button, 'no_bridge');
    return;
  }
  var request = { button: button };
  current = request;
  setState(button, 'loading');

  Promise.resolve().then(getText).then(function (text) {
    if (current !== request) return null;
    setState(button, 'loading');
    if (!text) return { ok: false, error: 'empty' };
    return bridge.callHandler('kwReadAloud', text);
  }).then(function (result) {
    if (current !== request) return; // stopped or replaced while loading
    if (!result || !result.ok) {
      current = null;
      showError(button, result && result.error);
      return;
    }
    request.url = audioUrl(result.audio, result.mimeType);
    request.audio = new Audio(request.url);
    request.audio.onended = function () {
      if (current === request) stop();
    };
    return request.audio.play().then(function () {
      if (current === request) setState(button, 'playing');
    });
  }).catch(function (e) {
    kwHab.log('read-aloud', 'failed', e);
    if (current === request) {
      stop();
      showError(button, 'playback');
    }
  });
}

function makeButton(getText) {
  var button = kwHab.fragment('read-aloud').querySelector('.kw-read-aloud');
  button.addEventListener('click', function (event) {
    // Keep Facebook from treating this as a click on the post or message.
    event.preventDefault();
    event.stopPropagation();
    read(button, getText);
  });
  return button;
}

function clean(text) {
  return (text || '')
    .replace(/(…|\.\.\.)?\s*See (more|less)\s*$/i, '')
    .replace(/\s+/g, ' ')
    .trim();
}

// ---- Feed posts: "Summarize post" ------------------------------------------

var POST = '[aria-posinset]';
var PROFILE_NAME = '[data-ad-rendering-role="profile_name"]';
var STORY_MESSAGE = '[data-ad-rendering-role="story_message"]';

function postAuthor(post) {
  var author = post.querySelector(PROFILE_NAME);
  // Only the name's first line: group posts add "· Join" / "· Follow" after it.
  return author ? clean(author.innerText.split('\n')[0]).replace(/\s*·.*$/, '') : '';
}

// The post's main photo: its largest Facebook image (not profile pictures,
// emoji or reaction icons), or null.
function postPhoto(post) {
  var best = null;
  var bestArea = 0;
  post.querySelectorAll('img').forEach(function (img) {
    var src = img.currentSrc || img.src || '';
    if (!/^https:\/\/[^/]*fbcdn\.net\//.test(src)) return;
    var area = img.clientWidth * img.clientHeight;
    if (img.clientWidth < 150 || img.clientHeight < 100 || area <= bestArea) return;
    best = src;
    bestArea = area;
  });
  return best;
}

// Shows [text] in a box under the post's button.
function showSummary(button, text) {
  var box = button.nextElementSibling;
  if (!box || !box.classList.contains('kw-post-summary')) {
    box = document.createElement('div');
    box.className = 'kw-post-summary';
    box.setAttribute('role', 'status');
    button.parentNode.insertBefore(box, button.nextSibling);
  }
  box.textContent = text;
}

// Opens a long post's "See more", so all of its words are used. Resolves once
// Facebook has had time to show them.
function expandPost(post) {
  var message = post.querySelector(STORY_MESSAGE);
  var more = message && Array.prototype.find.call(
    message.querySelectorAll('[role="button"]'),
    function (el) { return /^See more$/i.test((el.textContent || '').trim()); }
  );
  if (!more) return Promise.resolve();
  more.click();
  return new Promise(function (resolve) { setTimeout(resolve, 500); });
}

// What to say for [post]: a summary of its words and photo together, or just
// the words when there is no photo (or the photo can't be looked at).
function postSpeech(post, button) {
  return expandPost(post).then(function () { return describePost(post, button); });
}

function describePost(post, button) {
  var name = postAuthor(post);
  var message = post.querySelector(STORY_MESSAGE);
  var body = message ? clean(message.innerText) : '';
  var words = body ? (name ? name + ' wrote: ' + body : body) : '';
  var photo = postPhoto(post);
  if (!photo) return words;
  setState(button, 'looking');
  return window.flutter_inappwebview.callHandler(SUMMARY_HANDLER, name, body, photo)
    .then(function (result) {
      if (result && result.ok && result.summary) {
        showSummary(button, result.summary);
        return result.summary;
      }
      kwHab.log('read-aloud', 'no summary', result && result.error);
      return words ? words + ' There is also a photo.' : (name || 'Someone') + ' posted a photo.';
    });
}

// Adds the post's button to [parent], before [before] (null: at the end).
function addPostButton(post, parent, before) {
  if (!post || post.querySelector('.kw-read-aloud--post')) return;
  var button = makeButton(function () { return postSpeech(post, button); });
  button.classList.add('kw-read-aloud--post');
  button.setAttribute('data-idle-label', 'Summarize post');
  setState(button, 'idle');
  parent.insertBefore(button, before);
}

// Posts with words: the button goes right under them. The words are read when
// clicked, so a post expanded with "See more" is read in full.
kwHab.onElement(POST + ' ' + STORY_MESSAGE, function (message) {
  addPostButton(message.closest(POST), message.parentNode, message.nextSibling);
});

// Posts that are only a photo: the button goes above the photo.
kwHab.onElement(POST + ' a[href*="/photo"] img', function (img) {
  var post = img.closest(POST);
  if (!post || post.querySelector(STORY_MESSAGE) || post.querySelector('.kw-read-aloud--post')) return;
  var header = post.querySelector(PROFILE_NAME);
  if (!header) return;
  // The photo's section: its highest ancestor that doesn't also hold the header.
  var section = img;
  while (section.parentElement && !section.parentElement.contains(header)) {
    section = section.parentElement;
  }
  if (section.parentElement) addPostButton(post, section.parentElement, section);
});

// Chat messages: one button under each message. Facebook labels every message
// "At 10:36 PM, Collin: send credit card number", which already has the sender
// and the full text, so read "Collin said: …" (or "You said: …").
var MESSAGE = '[role="log"] [aria-roledescription="message"][data-scope="messages_table"]';

function messageSpeech(message) {
  var label = message.getAttribute('aria-label') || '';
  var match = /^At [^,]+, ([^:]+): ([\s\S]+)$/.exec(label);
  if (match) return clean(match[1]) + ' said: ' + clean(match[2]);
  return clean(message.innerText);
}

var ACTIONS = '[role="toolbar"][aria-label="Message actions"]';

// The message's hover icons (react, reply, more) live in a slot right after
// the bubble in the message's row. Returns that slot, or null.
function actionsSlot(message) {
  var slot = message.querySelector(ACTIONS);
  while (slot && slot.parentElement && slot.parentElement.parentElement !== message) {
    slot = slot.parentElement;
  }
  return slot && slot.parentElement ? slot : null;
}

function addMessageButton(message) {
  if (message.querySelector('.kw-read-aloud')) return;
  var next = message.nextElementSibling;
  if (next && next.classList.contains('kw-read-aloud-row')) return;
  // Photos, stickers and other messages without words get no button.
  var match = /^At [^,]+, ([^:]+): \S/.exec(message.getAttribute('aria-label') || '');
  if (!match) return;
  var button = makeButton(function () {
    return messageSpeech(message);
  });
  button.classList.add('kw-read-aloud--message');
  var slot = actionsSlot(message);
  if (slot) {
    // Beside the bubble, between it and the hover icons: left of the user's
    // own messages (the row is reversed), right of everyone else's. The cell
    // is opaque like Messenger's own slots, which hide the bubble gradient.
    var cell = document.createElement('div');
    cell.className = 'kw-read-aloud-cell';
    cell.appendChild(button);
    slot.parentNode.insertBefore(cell, slot);
    return;
  }
  // Unknown layout: a row of its own under the message, on the bubble's side.
  var row = document.createElement('div');
  row.className = 'kw-read-aloud-row';
  row.setAttribute('data-side', match[1] === 'You' ? 'end' : 'start');
  row.appendChild(button);
  message.parentNode.insertBefore(row, message.nextSibling);
}

kwHab.onElement(MESSAGE, addMessageButton);
// Messenger sometimes re-renders a message's row without replacing the
// message itself; put the button back when its hover icons reappear.
kwHab.onElement(MESSAGE + ' ' + ACTIONS, function (toolbar) {
  var message = toolbar.closest(MESSAGE);
  if (message) addMessageButton(message);
});

// Leaving the page (or switching chats) stops any reading.
kwHab.onNavigate(stop);
// So does turning read aloud off in Settings.
kwHab.onSettings(function (settings) {
  if (settings.readAloud !== true) stop();
});
