// "See more" / "See less" in post captions, reel captions and comments are
// bare text buttons. Tag them so css/see-more.css can draw them as boxed
// buttons. Only plain-text buttons inside caption text count, not the
// "See more" links in menus and lists (those wrap their text in spans).

var SEE_MORE = /^See (more|less)$/i;

kwHab.onElement('div[role="button"]:not([aria-label])', function (button) {
  if (button.children.length !== 0) return;
  if (!SEE_MORE.test(button.textContent.trim())) return;
  if (!button.closest('[dir="auto"]')) return;
  button.classList.add('kw-see-more');
});
