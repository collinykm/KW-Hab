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
(function () {
  if (window.kwHab) return;

  var htmlTemplates = __KW_HAB_HTML__;

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
