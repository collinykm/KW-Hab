// Friends home page: add an "All friends" section above "People you may know".
// The left sidebar (and its "All friends" link) is hidden by
// css/hide-left-column.css, so this keeps the friends list one click away.

function isFriendsHome() {
  return /^\/friends\/?$/.test(location.pathname);
}

// The outermost element that starts with the given heading: the whole section,
// without climbing into a container that also holds other sections or past
// the page's main area.
function sectionFor(heading) {
  var section = heading;
  while (
    section.parentElement &&
    section.parentElement.getAttribute('role') !== 'main' &&
    section.parentElement.innerText.trim().indexOf('People you may know') === 0
  ) {
    section = section.parentElement;
  }
  return section;
}

kwHab.onElement('h2', function (heading) {
  if (!isFriendsHome()) return;
  if (heading.textContent.trim() !== 'People you may know') return;
  var existing = document.querySelector('.kw-friends-all');
  if (existing) existing.remove();
  var section = sectionFor(heading);
  section.parentElement.insertBefore(kwHab.fragment('friends-all'), section);
});
