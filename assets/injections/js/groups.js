// A group's page: tags the header's "⋯" button for css/groups.css to hide.
// Other buttons are labelled "More" too, so only the one in the smallest box
// around the group's search button counts.

kwHab.onElement('[role="main"] [role="button"][aria-label="Search within this group"]', function (search) {
  var box = search.parentElement;
  for (var depth = 0; box && depth < 6; depth++, box = box.parentElement) {
    var more = box.querySelector('[role="button"][aria-label="More"]');
    if (more) {
      more.setAttribute('data-kw-hidden', 'groups');
      return;
    }
  }
});
