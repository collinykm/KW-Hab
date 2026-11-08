// The "Reels" carousel between posts in a feed. css/feed-reels.css hides its
// [data-virtualized] wrapper before it paints. Above that are several
// single-child wrappers, one of which has the margin to the next post; hiding
// only the inner one would leave that gap. So climb from [data-virtualized]
// through wrappers that hold nothing else, up to the feed list's child.

var HIDDEN = 'data-kw-feed-reels-hidden';
var CAROUSEL = '[role="grid"][aria-label="Reels"] [data-type="hscroll-child"]';

kwHab.onElement(CAROUSEL, function (item) {
  var unit = item.closest('[data-virtualized]');
  if (!unit || unit.hasAttribute(HIDDEN)) return;
  if (unit.parentElement && unit.parentElement.closest('[' + HIDDEN + ']')) return;
  while (unit.parentElement && unit.parentElement.children.length === 1 &&
         !unit.parentElement.matches('[role="main"], [role="feed"], body')) {
    unit = unit.parentElement;
  }
  unit.setAttribute(HIDDEN, '');
  kwHab.log('feed-reels', 'hid the Reels carousel', unit);
});
