// A post's header line ends "date · 🌐": an icon showing who the post is
// shared with (svg title "Shared with Public", "Shared with Friends",
// "Shared with Public group", …). Hide the icon and the " · " before it.
// Your own posts still have Edit audience in their ⋯ menu.

var AUDIENCE_HIDDEN = 'data-kw-post-audience-hidden';

kwHab.onElement('svg[title^="Shared with"]', function (icon) {
  // Climb to the cell holding only the icon, next to the " · " separator.
  var cell = icon;
  while (cell.parentElement && cell.parentElement.childElementCount === 1 &&
         cell.parentElement !== document.body) {
    cell = cell.parentElement;
  }
  cell.setAttribute(AUDIENCE_HIDDEN, '');
  var dot = cell.previousElementSibling;
  if (dot && dot.textContent.replace(/ /g, ' ').trim() === '·') {
    dot.setAttribute(AUDIENCE_HIDDEN, '');
  }
});
