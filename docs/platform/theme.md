<!-- summary: Which Color, Style and Border tokens exist, live theme switching, the Qt 6.12 Color singleton. -->
<!-- code: lib/**/*.qml -->
# Theme tokens in qs.Commons and qs.Ui

## Theme tokens

| Group | Tokens that exist |
|---|---|
| Popups | `Color.popups.background`, `.text`, `.border` |
| Menus | `Color.menu.background`, `.text`, `.border`, `.scrim`, `.selectedBackground`, `.selectedText`, `.selectedBorder` |
| Global | `Color.foreground`, `Color.accent`, `Color.urgent` |
| Bar | `Color.bar.background`, `.text`, `.active` (**no** `Color.bar.foreground`). `Ui.WidgetButton.foreground` resolves to the injected host's `bar.barForeground`; fall back to `Color.bar.text`. The stock Omarchy menu glyph uses `Style.font.body`; Station binds its mark directly to its `WidgetButton.foreground`. As of 2.1.9 its frame height follows the Omarchy menu glyph's `TextMetrics.tightBoundingRect.height` at `Style.font.body`; the indicator aligns to the same painted center. |
| Geometry/type | `Style.cornerRadius`, `Style.space(px)`, `Style.spacing.*`, `Style.font.*`, `Border.surfaceSpec(...)`, `BorderSurface` |

Themes switch live: the shell updates the singletons and bindings repaint. Do not hard-code palette values; Station's theme-token check fails on any hex colour (including short and alpha forms) and on symlinks. Do not copy Display's raw numeric spacing and font values.

## Qt 6.12 `Color` singleton (2026-11-21)

- **[SRC]** GitHub issue #24. qt6-declarative 6.12.0 exports `QtQuick/Color 6.12` in
  `QtQuick/plugins.qmltypes`. Of the names in `qs.Commons`, only `Color` collides.
- **[LIVE]** On this machine (qt6-declarative 6.12.0-4, quickshell 0.3.2),
  `omarchy agent look plugin` on Station 4.2.2 logged 20 errors such as
  `DisplayLayout.qml[17:-1]: TypeError: Cannot read property 'background' of undefined`
  and `Unable to assign [undefined] to QColor`, from 13 files that used a bare `Color`.
  With every use written as `Commons.Color` it logs none.
- **[QTTEST]** The QML harnesses did not catch it. `panel-composition` fails on any
  `TypeError` or `Unable to assign`, yet passed on 4.2.2 with none logged: the harnesses
  load stand-in `qs.Commons` modules, where the collision did not appear. Why the stand-in
  resolves differently is unexplained [INFER: module resolution order]. Only the
  real shell shows the bug. `qt-color-shadow.test.cjs` now rejects a bare `Color.`.
