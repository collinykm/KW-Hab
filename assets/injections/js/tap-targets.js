// Button size (onboarding "Button size" slider, kwHab.settings.buttonScale):
// makes everything you can click bigger, for people who find small targets
// hard to hit (e.g. hand tremors).
//
// Each clickable element is measured once at its normal size and tagged with
// data-kw-tap; css/tap-targets.css does the scaling, only while
// <html data-kw-big-taps> is set (button size above 100%):
//
//   compact  small and short controls (icon buttons, avatars, close "x",
//            "Like 62", top-bar tabs, "View 3 replies"): the whole control is
//            zoomed, icon, label and all, so a button's parts stay in step.
//   row      wide controls (menu items, full-width bars, text boxes): made
//            taller (min-height). If what's inside is short enough to fit at
//            double size (e.g. a full-width "View 3 replies" bar), that
//            content is zoomed (data-kw-tap-content); otherwise just its
//            small icons are (data-kw-tap-icon), and long text follows the
//            Text size setting.
//   inline   links inside running text ("See more", names): an invisible
//            hit area around the words, so the text doesn't move.
//   big      large areas (photos, cards): already easy to hit; untouched.
//
// Elements inside a compact control, or a row inside another row, are left
// alone so the scaling doesn't compound.
//
// Facebook often gives a control's wrapper a fixed size (e.g. a 40px column
// for a post's profile picture), so a grown control would spill over its
// neighbours. After scaling, wrappers that no longer contain their control
// are tagged data-kw-tap-fit and given a min-width/min-height to fit it.
// A grown control pushed out past the visible area (the window, or a
// scrolling panel such as the comments) lets its row wrap instead
// (data-kw-tap-wrap), so it moves to the next line rather than being cut off.

var CLICKABLE = [
  'a[href]', 'button', 'select', 'textarea', 'summary',
  'input:not([type="hidden"])',
  '[role="button"]', '[role="link"]', '[role="menuitem"]', '[role="menuitemradio"]',
  '[role="menuitemcheckbox"]', '[role="tab"]', '[role="option"]', '[role="switch"]',
  '[role="checkbox"]', '[role="radio"]', '[role="textbox"]', '[role="combobox"]',
].join(',');

// Thresholds, in CSS px at normal size.
var COMPACT_MAX_W = 200; // at most this wide and...
var COMPACT_MAX_H = 72; // ...this tall: zoom the whole control
var ROW_MAX_HEIGHT = 120; // taller than this: a card or photo, leave it
var ICON_MAX = 48; // icons inside rows that get zoomed
var MAX_SCALE = 2; // largest button size; row content must fit at this

var FIT_DEPTH = 4; // how many wrappers up to check for spill-over

var TAP = 'data-kw-tap';
var ICON = 'data-kw-tap-icon';
var CONTENT = 'data-kw-tap-content';
var FIT = 'data-kw-tap-fit';
var WRAP = 'data-kw-tap-wrap';
var CLIP_DEPTH = 15; // how far up to look for a scrolling/clipping panel
var WRAP_DEPTH = 6; // how far up to look for a row that can wrap
var BIG_TAPS = 'data-kw-big-taps';
var GROWN = '[' + TAP + '="compact"], [' + TAP + '="row"]';
var ICONS = 'svg, img, i[data-visualcompletion="css-img"]';

// ---- Turning it on and off ---------------------------------------------------

var currentScale = 1;

function enabled() {
  return currentScale > 1;
}

// Measuring forces layout, so nothing is watched or measured until the
// button size is first turned up: at 100% this script costs nothing while
// Facebook adds posts during scrolling.
var watching = false;

kwHab.onSettings(function (settings) {
  var scale = typeof settings.buttonScale === 'number' ? settings.buttonScale : 1;
  if (scale === currentScale) return;
  currentScale = scale;
  var root = document.documentElement;
  if (enabled()) root.setAttribute(BIG_TAPS, '');
  else root.removeAttribute(BIG_TAPS);
  if (enabled()) {
    if (!watching) {
      watching = true; // onElement also picks up everything already on the page
      kwHab.onElement(CLICKABLE, enqueue);
      kwHab.onElement(ICONS, enqueueIcon);
    } else {
      catchUp();
    }
  }
  refitAll();
});

// Controls added while the button size was back at 100% were skipped.
function catchUp() {
  document.querySelectorAll(CLICKABLE).forEach(function (el) {
    if (!el.hasAttribute(TAP)) enqueue(el);
  });
}

// ---- Classifying -------------------------------------------------------------

// Measuring forces layout (and briefly switches the enlargement off for the
// whole page), so new elements are queued and measured together. While
// scrolling, Facebook adds posts every few frames: waiting a little first
// turns those into one measurement instead of one per frame.
var queue = [];
var scheduled = false;
var BATCH_DELAY_MS = 120;

function enqueue(el) {
  if (!enabled()) return;
  queue.push(el);
  schedule();
}

function schedule() {
  if (scheduled) return;
  scheduled = true;
  setTimeout(function () { requestAnimationFrame(flush); }, BATCH_DELAY_MS);
}

// Icons that appear inside a row after it was measured. Facebook swaps them,
// e.g. a tab's outline icon for a filled one when it becomes the current tab.
var iconQueue = [];

function enqueueIcon(icon) {
  if (!enabled() || !icon.parentElement || !icon.parentElement.closest('[' + TAP + '="row"]')) return;
  iconQueue.push(icon);
  schedule();
}

// Not laid out yet (hidden menu, collapsed section): measure once it has a size.
var waitForSize = new ResizeObserver(function (entries) {
  entries.forEach(function (entry) {
    if (entry.contentRect.width === 0 && entry.contentRect.height === 0) return;
    waitForSize.unobserve(entry.target);
    enqueue(entry.target);
  });
});

function flush() {
  scheduled = false;
  var batch = queue;
  queue = [];
  if (!enabled()) {
    iconQueue = [];
    return;
  }
  // Measure at normal size: switch the enlargement off while reading (it is
  // back on before the frame is painted, so nothing flickers). Otherwise a
  // control already grown by something around it (e.g. a top-bar tab, which
  // follows the taller bar) would be scaled twice.
  var root = document.documentElement;
  var wasOn = root.hasAttribute(BIG_TAPS);
  if (wasOn) root.removeAttribute(BIG_TAPS);
  var measured = batch.map(measure);
  var icons = iconQueue.filter(function (icon) {
    if (!icon.isConnected || icon.hasAttribute(ICON)) return false;
    var r = icon.getBoundingClientRect();
    return r.width > 0 && r.width <= ICON_MAX && r.height <= ICON_MAX;
  });
  iconQueue = [];
  if (wasOn) root.setAttribute(BIG_TAPS, '');

  markIcons(icons);

  var grown = [];
  measured.forEach(function (m) {
    if (m && classify(m)) grown.push(m.el);
  });
  scheduleFit(grown);
}

function measure(el) {
  if (!el.isConnected || el.hasAttribute(TAP)) return null;
  var rect = el.getBoundingClientRect();
  var m = { el: el, w: rect.width, h: rect.height, display: getComputedStyle(el).display, icons: [], content: null };
  // Would be a row: also measure its content and icons now, at normal size.
  if (!isInline(m.display) && !isCompact(m) && m.h <= ROW_MAX_HEIGHT) {
    m.content = shortContent(el, rect);
    if (m.content) return m;
    var icons = el.querySelectorAll(ICONS);
    for (var i = 0; i < icons.length; i++) {
      var r = icons[i].getBoundingClientRect();
      if (r.width > 0 && r.width <= ICON_MAX && r.height <= ICON_MAX) m.icons.push(icons[i]);
    }
  }
  return m;
}

// The elements that make up a row's visible content, if together they are
// narrow enough to zoom to MAX_SCALE inside the row; otherwise null.
// Walks down single-child wrappers until the content is narrower than the
// row or splits into several pieces. Overlays (position: absolute, e.g.
// Facebook's hover highlight) don't count.
function shortContent(row, rowRect) {
  var node = row;
  for (var depth = 0; depth < 8; depth++) {
    var kids = Array.prototype.filter.call(node.children, function (k) {
      var r = k.getBoundingClientRect();
      return r.width > 0 && r.height > 0 && getComputedStyle(k).position !== 'absolute';
    });
    if (!kids.length) return null;
    if (kids.length === 1 && kids[0].getBoundingClientRect().width >= rowRect.width - 1) {
      node = kids[0];
      continue;
    }
    var left = Infinity;
    var right = -Infinity;
    kids.forEach(function (k) {
      var r = k.getBoundingClientRect();
      left = Math.min(left, r.left);
      right = Math.max(right, r.right);
    });
    return (right - left) * MAX_SCALE <= rowRect.width ? kids : null;
  }
  return null;
}

function isInline(display) {
  return display === 'inline' || display === 'contents';
}

function isCompact(m) {
  return m.w <= COMPACT_MAX_W && m.h <= COMPACT_MAX_H;
}

// Tags el; returns true if it is a control that grows (compact or row).
function classify(m) {
  var el = m.el;
  var parent = el.parentElement;
  // Already scaled as part of a bigger control.
  if (parent && parent.closest('[' + TAP + '="compact"]')) return false;

  if (m.w === 0 && m.h === 0) {
    waitForSize.observe(el); // fires once it's shown and has a size
    return false;
  }

  if (isInline(m.display)) {
    el.setAttribute(TAP, 'inline');
  } else if (isCompact(m)) {
    el.setAttribute(TAP, 'compact');
    return true;
  } else if (m.h <= ROW_MAX_HEIGHT && !(parent && parent.closest('[' + TAP + '="row"]'))) {
    el.style.setProperty('--kw-tap-h', m.h + 'px');
    el.setAttribute(TAP, 'row');
    if (m.content) {
      m.content.forEach(function (c) { c.setAttribute(CONTENT, ''); });
    } else {
      markIcons(m.icons);
    }
    return true;
  } else {
    el.setAttribute(TAP, 'big');
  }
  return false;
}

// Small icons and avatars inside a row grow with it (measured in [measure]).
function markIcons(icons) {
  icons.forEach(function (icon) {
    // Nested svgs/images: only the outermost one.
    if (icon.parentElement.closest('[' + ICON + ']')) return;
    if (icon.closest('[' + TAP + '="compact"]')) return;
    icon.setAttribute(ICON, '');
  });
}

// ---- Making room ---------------------------------------------------------------

// Fitting needs the grown sizes, so it runs a frame after classifying.
var fitQueue = [];
var fitScheduled = false;

function scheduleFit(els) {
  if (!els.length) return;
  Array.prototype.push.apply(fitQueue, els);
  if (fitScheduled) return;
  fitScheduled = true;
  requestAnimationFrame(fit);
}

function fit() {
  fitScheduled = false;
  var batch = fitQueue;
  fitQueue = [];
  if (!enabled()) return;
  // Read: for each control, the wrappers it spills out of and by how much.
  var growth = [];
  var wraps = [];
  batch.forEach(function (el) {
    if (!el.isConnected) return;
    var r = el.getBoundingClientRect();
    if (r.width === 0 && r.height === 0) return;
    // The control's normal size: compact ones are zoomed as a whole; rows
    // only got taller.
    var compact = el.getAttribute(TAP) === 'compact';
    var normalW = compact ? r.width / currentScale : r.width;
    var normalH = compact ? r.height / currentScale : parseFloat(el.style.getPropertyValue('--kw-tap-h')) || r.height;
    var wrapper = el.parentElement;
    for (var i = 0; i < FIT_DEPTH && wrapper && wrapper !== document.body; i++) {
      var w = wrapper.getBoundingClientRect();
      // display: contents wrappers have no box of their own; look past them.
      if (w.width === 0 && w.height === 0 && getComputedStyle(wrapper).display === 'contents') {
        wrapper = wrapper.parentElement;
        i--;
        continue;
      }
      // Only where the wrapper held the control at normal size: some are
      // deliberately smaller (e.g. 0px tall) and let it overflow.
      var needW = r.width > w.width + 0.5 && w.width + 0.5 >= normalW ? r.width : 0;
      var needH = r.height > w.height + 0.5 && w.height + 0.5 >= normalH ? r.height : 0;
      if (!needW && !needH) break; // fits (or never held it); so do the ones above
      growth.push({ wrapper: wrapper, w: needW, h: needH });
      wrapper = wrapper.parentElement;
    }
    if (r.right > visibleRight(el) + 1) {
      var row = wrappableRow(el);
      if (row) wraps.push(row);
    }
  });
  // Write.
  growth.forEach(function (g) {
    var style = g.wrapper.style;
    if (g.w > (parseFloat(style.getPropertyValue('--kw-fit-w')) || 0)) {
      style.setProperty('--kw-fit-w', g.w + 'px');
    }
    if (g.h > (parseFloat(style.getPropertyValue('--kw-fit-h')) || 0)) {
      style.setProperty('--kw-fit-h', g.h + 'px');
    }
    g.wrapper.setAttribute(FIT, '');
  });
  wraps.forEach(function (row) { row.setAttribute(WRAP, ''); });
}

// Right edge of the area el can be seen in: the nearest ancestor that clips
// or scrolls sideways, or the window.
function visibleRight(el) {
  var right = window.innerWidth;
  var node = el.parentElement;
  for (var i = 0; i < CLIP_DEPTH && node && node !== document.body; i++) {
    if (getComputedStyle(node).overflowX !== 'visible') {
      return Math.min(right, node.getBoundingClientRect().right);
    }
    node = node.parentElement;
  }
  return right;
}

// The nearest single-line flex row around el with more than one item.
function wrappableRow(el) {
  var node = el.parentElement;
  for (var i = 0; i < WRAP_DEPTH && node && node !== document.body; i++) {
    var style = getComputedStyle(node);
    if (/flex$/.test(style.display) && /^row/.test(style.flexDirection) &&
        style.flexWrap === 'nowrap' && node.children.length > 1) {
      return node;
    }
    node = node.parentElement;
  }
  return null;
}

// The button size changed: sizes from the old scale no longer apply.
function refitAll() {
  document.querySelectorAll('[' + FIT + ']').forEach(function (el) {
    el.removeAttribute(FIT);
    el.style.removeProperty('--kw-fit-w');
    el.style.removeProperty('--kw-fit-h');
  });
  document.querySelectorAll('[' + WRAP + ']').forEach(function (el) {
    el.removeAttribute(WRAP);
  });
  if (enabled()) scheduleFit(Array.prototype.slice.call(document.querySelectorAll(GROWN)));
}

