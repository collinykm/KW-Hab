// Names in group posts link to the person's page inside that group
// (/groups/<group>/user/<id>/: their group intro and group posts), whose
// "View profile" button leads on to their profile. Go straight to the
// profile instead: links are rewritten when clicked, and a group member page
// reached any other way (Back, a typed address) is replaced by the profile.

var GROUP_MEMBER = /^\/groups\/[^/]+\/user\/([^/?#]+)/;

function profileFor(id) {
  return /^\d+$/.test(id) ? '/profile.php?id=' + id : '/' + encodeURIComponent(id) + '/';
}

document.addEventListener('click', function (e) {
  if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
  var link = e.target.closest && e.target.closest('a[href]');
  if (!link) return;
  var url = new URL(link.href, location.href);
  if (url.host !== location.host) return;
  var m = url.pathname.match(GROUP_MEMBER);
  if (!m) return;
  e.preventDefault();
  e.stopPropagation();
  kwHab.log('profile-links', 'group member link -> profile', m[1]);
  location.assign(profileFor(m[1]));
}, true);

kwHab.onNavigate(function () {
  var m = location.pathname.match(GROUP_MEMBER);
  if (!m) return;
  kwHab.log('profile-links', 'group member page -> profile', m[1]);
  location.replace(profileFor(m[1]));
});
