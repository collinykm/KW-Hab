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

## Seeing changes

Asset files are bundled at build time. With `flutter run -d macos` running,
press `R` (hot restart) to rebuild the web view with your new files. Debug
builds have the Web Inspector enabled: right-click the page → Inspect Element.
