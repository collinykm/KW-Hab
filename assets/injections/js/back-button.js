// A "Back" button just below the top bar on the left, on every page and above
// Facebook's own windows, so the user can always return to the last page.

var button = null;

// The Navigation API knows exactly; older WebKit only has the history length.
function canGoBack() {
  return window.navigation ? window.navigation.canGoBack : history.length > 1;
}

function update() {
  if (!button) return;
  var can = canGoBack();
  button.setAttribute('aria-disabled', can ? 'false' : 'true');
  button.setAttribute('data-kw-can-go-back', can ? 'true' : 'false');
}

function add() {
  if (!button) {
    button = kwHab.fragment('back-button').querySelector('.kw-back');
    button.addEventListener('click', function (event) {
      event.preventDefault();
      event.stopPropagation();
      if (canGoBack()) history.back();
    });
  }
  if (!button.isConnected) document.body.appendChild(button);
  update();
}

// onNavigate also fires when Facebook replaces the page's contents.
kwHab.onNavigate(add);
if (window.navigation) window.navigation.addEventListener('currententrychange', update);

// The left-column titles that sit where the button goes: css/back-button.css
// moves them to its right.
kwHab.onElement('h1', function (title) {
  if (/^(Chats|Saved)$/.test(title.textContent.trim())) title.classList.add('kw-back-room');
});
