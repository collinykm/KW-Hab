// "Fix an old photo": a button under the "What's on your mind" box opens a
// window where the user picks a picture of an old photo. Cloudinary, through
// the Dart side (lib/cloudinary/, the `kwPhotoFix` handler, so the API secret
// never enters this page), makes it clearer, takes away scratches and marks,
// and adds colour to black-and-white photos. The user sees before and after,
// then can post it (it goes into Facebook's own Create post window, and only
// the user can press Post) or save it.

var HANDLER = 'kwPhotoFix';
var MAX_SIDE = 2000;
var JPEG_QUALITY = 0.92;
var PROMPT = /^What's on your mind/i;
var PHOTO_BUTTON = '[role="button"][aria-label="Photo/video"]';

var ERRORS = {
  not_configured: "Fixing photos isn't set up yet.",
  unauthorized: "Fixing photos isn't set up yet.",
  not_enabled: "Fixing photos isn't set up yet.",
  limit: 'No more photo fixes are left for now. Try again later.',
  too_big: 'That photo is too big. Try a smaller one.',
  bad_image: "That file doesn't look like a photo. Try a different one.",
  timeout: 'That took too long. Try again.',
  network: "Couldn't connect. Check the internet, then try again.",
};
var DEFAULT_ERROR = 'Something went wrong. Try again.';

var dialog = null;
var picked = null; // { base64, dataUrl }
var result = null; // the fixed photo, as a data: URL
var runId = 0; // bumped to abandon a fix still in progress

function part(selector) { return dialog.querySelector(selector); }

function show(step) {
  dialog.querySelectorAll('[data-step]').forEach(function (el) {
    el.hidden = el.getAttribute('data-step') !== step;
  });
}

function call() {
  var bridge = window.flutter_inappwebview;
  if (!bridge || !bridge.callHandler) return Promise.resolve({ ok: false, error: 'no_bridge' });
  return bridge.callHandler.apply(bridge, [HANDLER].concat([].slice.call(arguments)));
}

function failed(code) {
  part('[data-error]').textContent = ERRORS[code] || DEFAULT_ERROR;
  show('error');
}

function dataUrl(response) {
  return 'data:' + response.mimeType + ';base64,' + response.image;
}

function isMonochrome(canvas) {
  var size = 64;
  var small = document.createElement('canvas');
  small.width = small.height = size;
  var context = small.getContext('2d', { willReadFrequently: true });
  context.drawImage(canvas, 0, 0, size, size);
  var data = context.getImageData(0, 0, size, size).data;
  var coloured = 0, x = 0, y = 0, saturation = 0;
  for (var i = 0; i < data.length; i += 4) {
    var r = data[i], g = data[i + 1], b = data[i + 2];
    var max = Math.max(r, g, b), min = Math.min(r, g, b);
    var delta = max - min;
    var s = max ? delta / max : 0;
    if (s < 0.08 || delta < 8) continue;
    coloured++;
    saturation += s;
    var hue = max === r ? (g - b) / delta : max === g ? 2 + (b - r) / delta : 4 + (r - g) / delta;
    var angle = hue * Math.PI / 3;
    x += Math.cos(angle);
    y += Math.sin(angle);
  }
  var total = size * size;
  if (coloured < total * 0.1) return true; // practically grey
  // Sepia and other old tints: everything is one faint hue.
  var sameHue = Math.sqrt(x * x + y * y) / coloured;
  return sameHue > 0.85 && saturation / coloured < 0.45;
}

// Shrinks the file to a size Cloudinary takes quickly, then shows it.
function prepare(file) {
  var url = URL.createObjectURL(file);
  var image = new Image();
  image.onload = function () {
    URL.revokeObjectURL(url);
    var scale = Math.min(1, MAX_SIDE / Math.max(image.naturalWidth, image.naturalHeight));
    var canvas = document.createElement('canvas');
    canvas.width = Math.max(1, Math.round(image.naturalWidth * scale));
    canvas.height = Math.max(1, Math.round(image.naturalHeight * scale));
    canvas.getContext('2d').drawImage(image, 0, 0, canvas.width, canvas.height);
    var jpeg = canvas.toDataURL('image/jpeg', JPEG_QUALITY);
    picked = { dataUrl: jpeg, base64: jpeg.split(',')[1] };
    part('[data-image="picked"]').src = jpeg;
    part('[data-option="colour"]').checked = isMonochrome(canvas);
    show('ready');
  };
  image.onerror = function () {
    URL.revokeObjectURL(url);
    failed('bad_image');
  };
  image.src = url;
}

function setStatus(text) { part('[data-status]').textContent = text; }

function finish(afterUrl, note) {
  result = afterUrl;
  part('[data-image="before"]').src = picked.dataUrl;
  part('[data-image="after"]').src = afterUrl;
  part('[data-note]').textContent = note;
  show('done');
}

function fix() {
  if (!picked) return;
  var mine = ++runId;
  var colour = part('[data-option="colour"]').checked;
  var restored = null;
  part('[data-image="progress"]').src = picked.dataUrl;
  setStatus('Step 1 of 2: Making your photo clearer…');
  show('working');

  call('start', picked.base64, colour).then(function (started) {
    if (mine !== runId) return null;
    if (!started || !started.ok) throw (started && started.error) || 'failed';
    return call('restore', started.job).then(function (response) {
      if (mine !== runId) return null;
      if (!response || !response.ok) throw (response && response.error) || 'failed';
      restored = dataUrl(response);
      part('[data-image="progress"]').src = restored;
      setStatus(colour ? 'Step 2 of 2: Removing scratches and adding colour…'
                       : 'Step 2 of 2: Removing scratches and marks…');
      return call('repair', started.job);
    });
  }).then(function (response) {
    if (mine !== runId || !response) return;
    if (!response.ok) {
      // Step 1 still made it better: keep that.
      kwHab.log('photo-fix', 'repair failed', response.error);
      finish(restored, colour
        ? "We made your photo clearer, but couldn't add colour this time."
        : "We made your photo clearer, but couldn't take away the scratches this time.");
      return;
    }
    finish(dataUrl(response), colour
      ? "The colours are the computer's best guess, and faces may look a little different."
      : 'Faces may look a little different from the original.');
  }).catch(function (error) {
    if (mine !== runId) return;
    kwHab.log('photo-fix', 'failed', error);
    failed(typeof error === 'string' ? error : 'failed');
  });
}

function photoFile() {
  var binary = atob(result.split(',')[1]);
  var bytes = new Uint8Array(binary.length);
  for (var i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return new File([bytes], 'fixed-photo.jpg', { type: 'image/jpeg' });
}

// Facebook's own photo picker for the "What's on your mind" box.
function composerInput() {
  var inputs = document.querySelectorAll('input[type="file"][accept*="image"]');
  for (var i = 0; i < inputs.length; i++) {
    if (!inputs[i].closest('[role="dialog"]') && !inputs[i].closest('.kw-photo-fix')) return inputs[i];
  }
  return null;
}

// Hands the photo to Facebook, which opens Create post with it attached. The
// user still writes the post and presses Post.
function post() {
  var input = composerInput();
  if (!input) {
    part('[data-note]').textContent = 'Go to your Home page first, then press Post this photo again.';
    return;
  }
  var transfer = new DataTransfer();
  transfer.items.add(photoFile());
  input.files = transfer.files;
  input.dispatchEvent(new Event('change', { bubbles: true }));
  close();
}

function save() {
  var link = document.createElement('a');
  link.href = result;
  link.download = 'fixed-photo.jpg';
  document.body.appendChild(link);
  link.click();
  link.remove();
  part('[data-note]').textContent = 'Saved to your Downloads folder.';
}

function restart() {
  runId++;
  picked = null;
  result = null;
  show('choose');
}

function close() {
  runId++;
  if (dialog) dialog.hidden = true;
  document.removeEventListener('keydown', onKey, true);
}

function onKey(event) {
  if (event.key === 'Escape') {
    event.stopPropagation();
    close();
  }
}

var ACTIONS = {
  close: close,
  choose: function () { part('.kw-photo-fix__file').click(); },
  fix: fix,
  retry: function () { if (picked) fix(); else restart(); },
  restart: restart,
  post: post,
  save: save,
};

function build() {
  dialog = kwHab.fragment('photo-fix').querySelector('.kw-photo-fix');
  dialog.hidden = true;
  dialog.addEventListener('click', function (event) {
    if (event.target === dialog) return close(); // the dark area around the window
    var button = event.target.closest('[data-action]');
    if (button) ACTIONS[button.getAttribute('data-action')]();
  });
  part('.kw-photo-fix__file').addEventListener('change', function (event) {
    var file = event.target.files[0];
    event.target.value = ''; // so choosing the same file again still works
    if (file) prepare(file);
  });
  document.body.appendChild(dialog);
}

function open() {
  if (!dialog || !dialog.isConnected) build();
  restart();
  dialog.hidden = false;
  document.addEventListener('keydown', onKey, true);
  part('.kw-photo-fix__close').focus();
}

function makeOpenButton() {
  var button = kwHab.fragment('photo-fix').querySelector('.kw-photo-fix-open');
  button.addEventListener('click', function (event) {
    event.preventDefault();
    event.stopPropagation();
    open();
  });
  return button;
}

// The row with the "What's on your mind" box and its Photo/video shortcut.
function composerRow(photoButton) {
  for (var el = photoButton.parentElement, depth = 0; el && depth < 10; el = el.parentElement, depth++) {
    var buttons = el.querySelectorAll('[role="button"]');
    for (var i = 0; i < buttons.length; i++) {
      if (PROMPT.test((buttons[i].textContent || '').trim())) return el;
    }
  }
  return null;
}

kwHab.onElement(PHOTO_BUTTON, function (photoButton) {
  if (photoButton.closest('[role="dialog"]')) return;
  var row = composerRow(photoButton);
  if (!row || !row.parentElement) return;
  var next = row.nextElementSibling;
  if (next && next.classList.contains('kw-photo-fix-open')) return;
  row.parentElement.insertBefore(makeOpenButton(), row.nextSibling);
});

// Leaving the page abandons a fix in progress and closes the window.
kwHab.onNavigate(function () {
  if (dialog && !dialog.hidden) close();
});
