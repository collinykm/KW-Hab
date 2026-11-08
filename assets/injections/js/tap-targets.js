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
//            zoomed, icon, padding and all, so a button's parts stay in step.
//   row      wide controls (menu items, full-width bars, text boxes): made
//            taller (min-height), up to a comfortable height; ones already
//            that tall (cards, two-line rows) stay as they are. If what's
//            inside is short enough to fit at double size (e.g. a full-width
//            "View 3 replies" bar), that content is zoomed
//            (data-kw-tap-content); otherwise just its small icons are
//            (data-kw-tap-icon).
//
// Words follow the Text size setting only, never Text size times Button
// size: the words in a zoomed control are tagged data-kw-tap-text with their
// normal size, and the CSS shrinks them back by the zoom. This is how the
// app's own Settings screen sizes its buttons too.
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

// Thresholds, in CSS px at normal size. The height limits grow with the text
// size (see textGrown), so a button whose label made it taller is still
// treated like the buttons beside it. Widths mostly come from the layout
// (full-width rows), so the width limit stays.
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
var TEXT = 'data-kw-tap-text';
var FILL = 'data-kw-tap-fill';
var CLIP_DEPTH = 15; // how far up to look for a scrolling/clipping panel
var WRAP_DEPTH = 6; // how far up to look for a row that can wrap
var BIG_TAPS = 'data-kw-big-taps';
var GROWN = '[' + TAP + '="compact"], [' + TAP + '="row"]';
var ICONS = 'svg, img, i[data-visualcompletion="css-img"]';

// ---- Turning it on and off ---------------------------------------------------

var currentScale = 1;
var currentTextScale = 1;

function enabled() {
  return currentScale > 1;
}

// Measuring forces layout, so nothing is watched or measured until the
// button size is first turned up: at 100% this script costs nothing while
// Facebook adds posts during scrolling.
var watching = false;

function onSettings(settings) {
  var scale = typeof settings.buttonScale === 'number' ? settings.buttonScale : 1;
  var textScale = typeof settings.textScale === 'number' ? settings.textScale : 1;
  if (scale === currentScale && textScale === currentTextScale) return;
  // Sizes were measured with the old text size: measure everything again.
  var remeasure = watching && textScale !== currentTextScale;
  currentScale = scale;
  currentTextScale = textScale;
  var root = document.documentElement;
  if (enabled()) root.setAttribute(BIG_TAPS, '');
  else root.removeAttribute(BIG_TAPS);
  if (remeasure) resetAll();
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
}

// Forgets every measurement, so the next catchUp() measures afresh.
function resetAll() {
  var attrs = [TAP, ICON, CONTENT, TEXT, FILL];
  document.querySelectorAll(attrs.map(function (a) { return '[' + a + ']'; }).join(',')).forEach(function (el) {
    attrs.forEach(function (a) { el.removeAttribute(a); });
    ['--kw-tap-h', '--kw-tap-fs', '--kw-tap-lh'].forEach(function (p) { el.style.removeProperty(p); });
  });
}

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
  measureTexts(measured.reduce(function (all, m) { return m ? all.concat(m.texts) : all; }, []));
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
  var m = { el: el, w: rect.width, h: rect.height, display: getComputedStyle(el).display, icons: [], content: null, texts: [], fill: [] };
  if (isInline(m.display)) return m;
  // Would be zoomed: measure its words now, at normal size.
  if (isCompact(m)) {
    m.texts = textsIn([el]);
    return m;
  }
  // Would be a row: also measure its content and icons now, at normal size.
  if (m.h <= textGrown(ROW_MAX_HEIGHT)) {
    m.fill = fillChain(el, rect);
    m.content = shortContent(el, rect);
    if (m.content) {
      m.texts = textsIn(m.content);
      return m;
    }
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

// The elements holding the words inside roots, each with its font size and
// line height in rem (so they still follow a later Text size change).
function textsIn(roots) {
  var seen = [];
  var out = [];
  roots.forEach(function (root) {
    var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    for (var node = walker.nextNode(); node; node = walker.nextNode()) {
      var el = node.parentElement;
      if (!el || seen.indexOf(el) >= 0 || !node.nodeValue.trim()) continue;
      seen.push(el);
      if (el.closest('svg') || el.hasAttribute(TEXT)) continue;
      out.push({ el: el });
    }
    // Text boxes: what's typed in them.
    var fields = Array.prototype.slice.call(root.querySelectorAll('input, textarea'));
    if (root.matches('input, textarea')) fields.push(root);
    fields.forEach(function (field) {
      if (!field.hasAttribute(TEXT)) out.push({ el: field });
    });
    // Words Facebook draws as an <svg> (e.g. a post's "5 days ago"): the
    // whole drawing is shrunk back instead.
    root.querySelectorAll('svg').forEach(function (svg) {
      if (svgText(svg) && !svg.parentElement.closest('svg')) out.push({ el: svg, svg: true });
    });
  });
  return out;
}

// Each word's font size and line height at the normal text size, in rem.
// Read with the page's text size briefly set back to normal (16px), so
// words Facebook sizes in px (e.g. a comment's "Reply") are caught too: the
// CSS then sizes every word by the Text size setting, the way rem-sized
// words already are. Only reads styles, so no layout is done twice.
function measureTexts(texts) {
  if (!texts.length) return;
  var root = document.documentElement;
  root.style.setProperty('font-size', '16px', 'important');
  texts.forEach(function (t) {
    if (t.svg) return;
    var style = getComputedStyle(t.el);
    t.fs = parseFloat(style.fontSize) / 16;
    t.lh = parseFloat(style.lineHeight) / 16; // NaN for "normal"
  });
  root.style.removeProperty('font-size');
}

// Facebook draws some words as <use> references to <text> drawn elsewhere,
// sometimes through a chain of references.
function svgText(node) {
  for (var depth = 0; node && depth < 6; depth++) {
    if (node.tagName === 'text' || node.querySelector('text')) return true;
    var use = node.tagName === 'use' ? node : node.querySelector('use');
    var href = use && (use.getAttribute('href') || use.getAttribute('xlink:href'));
    node = href && href.charAt(0) === '#' ? document.getElementById(href.slice(1)) : null;
  }
  return false;
}

// Keeps words in a zoomed control at the Text size setting
// (css/tap-targets.css undoes the zoom on them).
function markTexts(texts) {
  texts.forEach(function (t) {
    if (!t.el.isConnected || t.el.hasAttribute(TEXT)) return;
    if (t.svg) {
      t.el.setAttribute(TEXT, 'svg');
      return;
    }
    t.el.style.setProperty('--kw-tap-fs', t.fs + 'rem');
    if (isFinite(t.lh)) t.el.style.setProperty('--kw-tap-lh', t.lh + 'rem');
    t.el.setAttribute(TEXT, '');
  });
}

// The boxes inside a row that fill it exactly. Facebook often draws a
// button's background on such a child at a fixed height (e.g. a 36px grey
// "Post" bar inside the button), so these grow with the row; otherwise the
// button would get taller around a box that stays the same.
function fillChain(row, rect) {
  var chain = [];
  var node = row;
  for (var depth = 0; depth < 3; depth++) {
    var kids = Array.prototype.filter.call(node.children, function (k) {
      return !/^(absolute|fixed)$/.test(getComputedStyle(k).position);
    });
    if (kids.length !== 1) break;
    var r = kids[0].getBoundingClientRect();
    if (Math.abs(r.height - rect.height) > 1 || Math.abs(r.width - rect.width) > 1) break;
    chain.push(kids[0]);
    node = kids[0];
  }
  return chain;
}

function isInline(display) {
  return display === 'inline' || display === 'contents';
}

function isCompact(m) {
  return m.w <= COMPACT_MAX_W && m.h <= textGrown(COMPACT_MAX_H);
}

// A size limit at the current text size.
function textGrown(px) {
  return px * Math.max(1, currentTextScale);
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
    markTexts(m.texts);
    return true;
  } else if (m.h <= textGrown(ROW_MAX_HEIGHT) && !(parent && parent.closest('[' + TAP + '="row"]'))) {
    el.style.setProperty('--kw-tap-h', m.h + 'px');
    el.setAttribute(TAP, 'row');
    m.fill.forEach(function (f) {
      f.style.setProperty('--kw-tap-h', m.h + 'px');
      f.setAttribute(FILL, '');
    });
    if (m.content) {
      m.content.forEach(function (c) { c.setAttribute(CONTENT, ''); });
      markTexts(m.texts);
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

// ---- Start -------------------------------------------------------------------

// Last, once everything above is defined: onSettings calls back straight
// away, and with the button size already up that starts classifying, which
// needs the queues declared above.
kwHab.onSettings(onSettings);
