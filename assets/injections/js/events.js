// A single event's page (/events/<id>): tags the "⋯" button beside Share for
// css/events.css to hide. Other pages have buttons labelled "More" too.

kwHab.onElement('[role="main"] [role="button"][aria-label="More"]', function (more) {
  if (/^\/events\/\d+/.test(location.pathname)) more.setAttribute('data-kw-hidden', 'events');
});
