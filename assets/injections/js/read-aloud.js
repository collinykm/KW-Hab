// "Read aloud" buttons on feed posts and chat messages. The user starts
// reading themselves; the button becomes "Stop reading" while audio plays.
// Speech comes from ElevenLabs through the Dart side (lib/speech/), via the
// `kwReadAloud` handler, so the API key never enters this page.

var LABELS = {
  idle: 'Read aloud',
  loading: 'Getting audio…',
  playing: 'Stop reading',
};
var ERRORS = {
  not_configured: "Read aloud isn't set up yet",
  unauthorized: "Read aloud isn't set up yet",
  empty: 'Nothing to read here',
};
var DEFAULT_ERROR = "Couldn't read aloud. Try again.";

// The one thing being read right now: { button, audio, url } or { button } while loading.
var current = null;

function setState(button, state, message) {
  button.setAttribute('data-state', state);
  button.querySelector('.kw-read-aloud__label').textContent = message || LABELS[state];
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

function read(button, text) {
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

  bridge.callHandler('kwReadAloud', text).then(function (result) {
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
    read(button, getText());
  });
  return button;
}

function clean(text) {
  return (text || '')
    .replace(/(…|\.\.\.)?\s*See (more|less)\s*$/i, '')
    .replace(/\s+/g, ' ')
    .trim();
}

// Feed posts: the author's name, then the post text (read when clicked, so a
// post expanded with "See more" is read in full).
kwHab.onElement('[aria-posinset] [data-ad-rendering-role="story_message"]', function (message) {
  var post = message.closest('[aria-posinset]');
  if (!post || post.querySelector('.kw-read-aloud')) return;
  var button = makeButton(function () {
    var author = post.querySelector('[data-ad-rendering-role="profile_name"]');
    // Only the name's first line: group posts add "· Join" / "· Follow" after it.
    var name = author ? clean(author.innerText.split('\n')[0]).replace(/\s*·.*$/, '') : '';
    var body = clean(message.innerText);
    return name ? name + ' wrote: ' + body : body;
  });
  button.classList.add('kw-read-aloud--post');
  message.parentNode.insertBefore(button, message.nextSibling);
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
