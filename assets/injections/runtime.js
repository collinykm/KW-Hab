// Shared helpers for every file in js/. Loaded once per page, before any
// area script. Owned by the core shell. Area scripts should use these rather
// than adding their own observers or history patches.
//
//   kwHab.html(name)               -> contents of html/<name>.html as a string
//   kwHab.fragment(name)           -> the same, parsed into a DocumentFragment
//   kwHab.onNavigate(cb)           -> cb(location) on load and on every in-app
//                                     URL change (Facebook is a single-page app)
//   kwHab.onElement(selector, cb)  -> cb(el) once for each element matching
//                                     selector, now and whenever one appears
//   kwHab.log(area, ...args)       -> console.log tagged with the area name
//   kwHab.settings                 -> the user's accessibility settings (a copy):
//                                     { textScale, boldText, buttonScale,
//                                       readAloud, talkToType }
//   kwHab.onSettings(cb)           -> cb(settings) now and whenever they change
//                                     (settings change live, without a reload)
//
// The same settings are also on <html> for CSS:
//   --kw-text-scale, --kw-button-scale   numbers, e.g. calc(40px * var(--kw-button-scale))
//   [data-kw-bold-text] [data-kw-read-aloud] [data-kw-talk-to-type]
//                                        present only when that feature is on
(function () {
  if (window.kwHab) return;

  var htmlTemplates = __KW_HAB_HTML__;

  // Settings arrive from Dart (lib/settings/page_settings_bridge.dart), which
  // sets window.__kwHabSettings and calls _applySettings on changes.
  var settings = {};
  var settingsCallbacks = [];
  var SETTING_ATTRS = {
    boldText: 'data-kw-bold-text',
    readAloud: 'data-kw-read-aloud',
    talkToType: 'data-kw-talk-to-type',
  };
  var SETTING_VARS = { textScale: '--kw-text-scale', buttonScale: '--kw-button-scale' };
  function copySettings() {
    var copy = {};
    Object.keys(settings).forEach(function (k) { copy[k] = settings[k]; });
    return copy;
  }
  // Idempotent: only touches <html> when a value differs, so the observer
  // below (which restores them if Facebook rewrites <html>) can't loop.
  function applySettingsToRoot() {
    var root = document.documentElement;
    if (!root) return;
    Object.keys(SETTING_ATTRS).forEach(function (key) {
      var attr = SETTING_ATTRS[key];
      if (settings[key] === true) {
        if (!root.hasAttribute(attr)) root.setAttribute(attr, '');
      } else if (root.hasAttribute(attr)) {
        root.removeAttribute(attr);
      }
    });
    Object.keys(SETTING_VARS).forEach(function (key) {
      var value = String(typeof settings[key] === 'number' ? settings[key] : 1);
      if (root.style.getPropertyValue(SETTING_VARS[key]) !== value) {
        root.style.setProperty(SETTING_VARS[key], value);
      }
    });
  }
  function applySettings(next) {
    settings = next && typeof next === 'object' ? next : {};
    applySettingsToRoot();
    settingsCallbacks.forEach(function (cb) {
      try { cb(copySettings()); } catch (e) { console.error('[kwHab] onSettings', e); }
    });
  }
  function watchRoot() {
    applySettingsToRoot();
    new MutationObserver(applySettingsToRoot).observe(document.documentElement, {
      attributes: true,
      attributeFilter: ['style'].concat(Object.keys(SETTING_ATTRS).map(function (k) { return SETTING_ATTRS[k]; })),
    });
  }
  settings = window.__kwHabSettings || {};
  if (document.documentElement) {
    watchRoot();
  } else {
    new MutationObserver(function (_, observer) {
      if (!document.documentElement) return;
      observer.disconnect();
      watchRoot();
    }).observe(document, { childList: true });
  }

  var navCallbacks = [];
  var lastHref = null;
  function fireNavigate() {
    if (location.href === lastHref) return;
    lastHref = location.href;
    navCallbacks.forEach(function (cb) {
      try { cb(location); } catch (e) { console.error('[kwHab] onNavigate', e); }
    });
  }
  ['pushState', 'replaceState'].forEach(function (method) {
    var original = history[method];
    history[method] = function () {
      var result = original.apply(this, arguments);
      fireNavigate();
      return result;
    };
  });
  window.addEventListener('popstate', fireNavigate);

  var elementWatchers = [];
  var observer = null;
  function scan(watcher, root) {
    if (!root.querySelectorAll) return;
    var matches = root.querySelectorAll(watcher.selector);
    for (var i = 0; i < matches.length; i++) {
      var el = matches[i];
      if (el[watcher.key]) continue;
      el[watcher.key] = true;
      try { watcher.cb(el); } catch (e) { console.error('[kwHab] onElement', watcher.selector, e); }
    }
  }
  function ensureObserver() {
    if (observer) return;
    observer = new MutationObserver(function (mutations) {
      for (var m = 0; m < mutations.length; m++) {
        var added = mutations[m].addedNodes;
        for (var n = 0; n < added.length; n++) {
          var node = added[n];
          if (node.nodeType !== 1) continue;
          elementWatchers.forEach(function (w) {
            if (node.matches && node.matches(w.selector) && !node[w.key]) {
              node[w.key] = true;
              try { w.cb(node); } catch (e) { console.error('[kwHab] onElement', w.selector, e); }
            }
            scan(w, node);
          });
        }
      }
    });
    observer.observe(document.documentElement, { childList: true, subtree: true });
  }

  window.kwHab = {
    html: function (name) {
      if (!(name in htmlTemplates)) throw new Error('[kwHab] no html/' + name + '.html');
      return htmlTemplates[name];
    },
    fragment: function (name) {
      var t = document.createElement('template');
      t.innerHTML = window.kwHab.html(name);
      return t.content;
    },
    onNavigate: function (cb) {
      navCallbacks.push(cb);
      if (lastHref !== null) {
        try { cb(location); } catch (e) { console.error('[kwHab] onNavigate', e); }
      }
    },
    onElement: function (selector, cb) {
      var watcher = { selector: selector, cb: cb, key: '__kwHab' + elementWatchers.length };
      elementWatchers.push(watcher);
      scan(watcher, document);
      ensureObserver();
    },
    get settings() { return copySettings(); },
    onSettings: function (cb) {
      settingsCallbacks.push(cb);
      try { cb(copySettings()); } catch (e) { console.error('[kwHab] onSettings', e); }
    },
    _applySettings: applySettings,
    log: function (area) {
      var args = Array.prototype.slice.call(arguments, 1);
      console.log.apply(console, ['[kwHab:' + area + ']'].concat(args));
    },
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', fireNavigate);
  } else {
    fireNavigate();
  }
})();
