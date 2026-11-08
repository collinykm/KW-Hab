// Sponsored posts in feeds. The right-hand column (with its own Sponsored
// box) is already hidden by css/hide-right-column.css; this handles the ads
// mixed in between friends' posts.
//
// Facebook hides the "Ad"/"Sponsored" label from scripts: under the poster's
// name it is an <svg><use xlink:href="#SvgXyz"></svg> that draws an element
// kept elsewhere in the page, often through a chain of further <use>s. So the
// label is found by following the chain and reading the text at the end. Some ads also carry links only
// ads have, which are checked too:
//   - a[attributionsrc^="/privacy_sandbox/"]: ad click tracking
//   - a[href*="/ads/about"]: "Why am I seeing this ad?"
//   - a[aria-label="Sponsored"]: the label itself, when it is a plain link
// Each hidden post is logged (kwHab:ads) with the reason, so false positives
// can be checked in the Web Inspector console.

var HIDDEN = 'data-kw-ads-hidden';
var LINKS = [
  'a[attributionsrc^="/privacy_sandbox/"]',
  'a[href*="/ads/about"]',
  'a[aria-label="Sponsored"]',
].join(', ');
var POST_MENU = '[aria-label^="Actions for this post"]';

// The whole feed unit, so no empty gap or divider is left behind.
function postOf(el) {
  if (el.closest('[role="dialog"]')) return null;

  var feed = el.closest('[role="feed"]');
  if (feed) {
    var unit = el;
    while (unit.parentElement && unit.parentElement !== feed) unit = unit.parentElement;
    return unit;
  }

  var post = el.closest('[aria-posinset]') || el.closest('[role="article"]');
  if (post) return post;

  // No feed markup: climb while the ancestor still holds only this one post
  // (one "Actions for this post" menu), stopping at the main column.
  var node = null;
  for (var cur = el; cur.parentElement; cur = cur.parentElement) {
    var parent = cur.parentElement;
    if (parent.matches('[role="main"], body')) break;
    var menus = parent.querySelectorAll(POST_MENU).length;
    if (menus > 1) break;
    if (menus === 1) node = parent;
  }
  return node;
}

function hide(el, reason) {
  var post = postOf(el);
  if (!post || post.hasAttribute(HIDDEN)) return;
  post.setAttribute(HIDDEN, '');
  kwHab.log('ads', 'hid a sponsored post (' + reason + ')', post);
}

kwHab.onElement(LINKS, function (link) {
  hide(link, 'ad link');
});

// <use> labels. The <use> points at an <svg> that is itself another <use>,
// often many deep, ending at a <text>. Follow every <use> down to the text it
// draws. Returns null while part of the chain isn't in the page yet.
var XLINK = 'http://www.w3.org/1999/xlink';
var MAX_HOPS = 50;

function useText(use, hops) {
  if (hops > MAX_HOPS) return '';
  var ref = use.getAttributeNS(XLINK, 'href') || use.getAttribute('xlink:href') ||
            use.getAttribute('href') || '';
  if (ref.charAt(0) !== '#') return null;
  var target = document.getElementById(ref.slice(1));
  return target ? drawnText(target, hops + 1) : null;
}

function drawnText(el, hops) {
  if (el.localName === 'use') return useText(el, hops);
  var text = '';
  for (var node = el.firstChild; node; node = node.nextSibling) {
    var part = node.nodeType === 3 ? node.nodeValue
      : node.nodeType === 1 ? drawnText(node, hops) : '';
    if (part === null) return null;
    text += part;
  }
  return text;
}

// Letters only, sorted, so a label drawn with its letters out of order
// ("dA") still matches.
function letters(text) {
  return text.toLowerCase().replace(/[^a-z]/g, '').split('').sort().join('');
}
var AD_LETTERS = ['ad', 'sponsored'].map(letters);

function checkPost(post) {
  if (post.hasAttribute(HIDDEN)) return true;
  var uses = post.querySelectorAll('a svg use');
  for (var i = 0; i < uses.length; i++) {
    var text = useText(uses[i], 0);
    if (text !== null && AD_LETTERS.indexOf(letters(text)) !== -1) {
      hide(uses[i], 'label "' + text.trim() + '"');
      return true;
    }
  }
  return false;
}

// Facebook fills in and swaps the label after the post appears, so each post
// is re-checked whenever it changes, and a few times on a timer for chains
// that finish outside the post.
function watchPost(post) {
  if (!post || post.__kwAdsWatched) return;
  post.__kwAdsWatched = true;
  var pending = null;
  var observer = new MutationObserver(function () {
    if (pending) return;
    pending = setTimeout(function () {
      pending = null;
      if (checkPost(post)) observer.disconnect();
    }, 100);
  });
  if (checkPost(post)) return;
  observer.observe(post, { subtree: true, childList: true, attributes: true, attributeFilter: ['href', 'xlink:href'] });
  [300, 1000, 3000].forEach(function (delay) {
    setTimeout(function () { if (checkPost(post)) observer.disconnect(); }, delay);
  });
}

kwHab.onElement(POST_MENU + ', a svg use', function (el) {
  watchPost(postOf(el));
});
