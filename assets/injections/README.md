# Facebook UI customizations

Everything in this folder is injected into every Facebook page the app loads.
**One file per area of the UI.** Files are discovered automatically, so adding
an area means adding files, never editing a shared list.

```
css/<area>.css    styles, applied before the page renders
js/<area>.js      behaviour, runs once the DOM is ready, isolated per file
html/<area>.html  markup templates, inserted by a js file via kwHab.fragment('<area>')
runtime.js        shared kwHab.* helpers (core shell, not an area)
```

Use the same `<area>` name across the three folders for one feature, e.g.
`css/left-nav.css`, `js/left-nav.js`, `html/left-nav.html`.

## Rules

- Lowercase kebab-case names. Files starting with `_` are ignored (templates/drafts).
- Files load in alphabetical order. Avoid relying on it. If you must, use a
  numeric prefix (`10-theme.css`).
- No subfolders: Flutter only bundles the folders listed in `pubspec.yaml`.
- Facebook's class names are obfuscated and change. Select on stable
  attributes: `role`, `aria-label`, `data-pagelet`, `href`.
- CSS is global. Scope by page from JS if needed: `kwHab.onNavigate` can set
  a `data-kw-page` attribute on `<html>` and the CSS can target that.
- Prefix any classes/ids you create with `kw-` so they never clash with Facebook's.

## User settings

The accessibility choices from onboarding reach every page (and change live,
without a reload):

- JS: `kwHab.settings` → `{ textScale, boldText, buttonScale, readAloud, talkToType }`,
  and `kwHab.onSettings(cb)` to react to changes.
- CSS: `var(--kw-text-scale)` / `var(--kw-button-scale)` (1 = normal) and the
  `html[data-kw-bold-text]`, `html[data-kw-read-aloud]`, `html[data-kw-talk-to-type]`
  attributes (present only when that feature is on).

`css/read-aloud.css` and `css/speech-to-text.css` hide their buttons unless
`html[data-kw-read-aloud]` / `html[data-kw-talk-to-type]` is set, and the Dart
bridges behind them refuse (`error: 'disabled'`) while the setting is off.

`css/accessibility.css` applies text size and bold text to the whole page.
`js/tap-targets.js` + `css/tap-targets.css` apply button size to everything
clickable: short controls (icons, "Like 62", tabs) are zoomed whole, wide ones
made taller (with their content zoomed if it's short), links in text get a
bigger invisible hit area, wrappers with a fixed size are grown to fit, and
rows whose controls get pushed out of view wrap onto a second line. Controls you add get this automatically. Words inside a zoomed control
follow the Text size setting only (never text size times button size), and
wide rows grow to at most 44px × the button size. If a scaled control breaks
your area's layout, fix it in your area's CSS under `html[data-kw-big-taps]`,
or opt an element out by giving it `data-kw-tap="big"` before it renders.

Size text you add in `rem`, never `px`, so it follows the Text size setting,
and multiply by `var(--kw-unzoom, 1)` so it isn't zoomed again inside a
zoomed control, e.g. `font-size: calc(0.8125rem * var(--kw-unzoom, 1))`.
Give boxes that hold text a `min-width`/`min-height` rather than a fixed
`width`/`height`, so bigger text doesn't spill out of them.
Support contacts are deliberately not available here (Facebook can read the
page).

## Seeing changes

Asset files are bundled at build time. With `flutter run -d macos` running,
press `R` (hot restart) to rebuild the web view with your new files. Debug
builds have the Web Inspector enabled: right-click the page → Inspect Element.
