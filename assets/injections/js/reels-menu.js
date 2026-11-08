// Hide the left "Reels" menu (For you / Following / Profile) on the Reels page.
// The column has no role or aria-label, so start from its "Following" link and
// climb to the outermost ancestor that is still menu-sized; css/reels-menu.css
// hides whatever gets tagged.

kwHab.onElement('a[href^="/reel/following"]', function (link) {
  requestAnimationFrame(function () {
    var panel = link;
    while (panel.parentElement) {
      var width = panel.parentElement.getBoundingClientRect().width;
      if (width === 0 || width >= 400) break;
      panel = panel.parentElement;
    }
    if (panel !== link) panel.setAttribute('data-kw-hidden', 'reels-menu');
  });
});
