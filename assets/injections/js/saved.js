// The Saved page (/saved/, opened from the top bar's Saved tab). Its gear
// button links to "Reminders Settings" (notifications, feed reminders, saved
// items in Feed). It is tagged here and css/saved.css hides it, so the page is
// just the user's saved items and collections.

kwHab.onElement('a[href*="/saved/settings"]', function (gear) {
  gear.setAttribute('data-kw-hidden', 'saved');
});
