<!-- summary: Every color, border and type token Station may use, and its role. -->
<!-- code: lib/**/*.qml -->
# Color and typography tokens

## Color tokens

No hex literals anywhere in Station. Every color is one of these, confirmed present in the installed `qs.Commons` [V, [Theme findings](../platform/theme.md#theme-tokens)]:

In QML, write every token as `Commons.Color.…` with `import qs.Commons as Commons`. The tables below shorten it to `Color.…`. Qt 6.12 adds its own `Color` singleton to `QtQuick`, and a bare `Color` can resolve to it, so every theme color reads as `undefined` [V, issue #24]. `test/unit/qt-color-shadow.test.cjs` rejects a bare `Color.` in Station's QML.

| Token | Role |
|---|---|
| `Color.popups.background` | Panel background |
| `Color.popups.text` | Default text |
| `Color.popups.border` | **Not a neutral border on the default theme** [V]. Omarchy's generated `shell.toml` maps `[popups] border` to the active-window-border color, i.e. the accent. Using it for a plain row or card border produces an unintended accent-blue box — this is exactly the "every row is bordered blue" bug found in this codebase. Never use it as a neutral border. |
| **Neutral row separator** | `Ui.PanelSeparator` [V] — the host's own hairline, drawn at a reduced-opacity foreground. This is the only correct way to separate rows with no box. |
| **Neutral control border** | `Border.controlSpec("normal", …)` [V, RESOLVED] — resolves to foreground at ~40% opacity, 1px. This is already what `Ui.Button { bordered: true }` and `Ui.Dropdown` paint by default, so using it for chip groups, display nodes and secondary actions makes them match controls Omarchy already ships, rather than inventing a fourth border weight. **Scope: this is for actual controls (buttons, dropdowns, chip groups, display nodes) — never for a List row container.** A List row stays fully borderless per [Components](components.md#rows-and-dropdowns), even now that a real neutral-border token exists; giving every row this border would recreate "every row is boxed," just in gray instead of blue. Use this, not `Color.popups.border`, anywhere a control needs an outline. |
| `Color.menu.background` | Dropdown menu background |
| `Color.menu.text` | Dropdown menu item text |
| `Color.menu.border` | Dropdown menu border |
| `Color.menu.selectedBackground` | Lifted fill for a selected Choice chip or a hovered menu row |
| `Color.menu.selectedText` | Text on a selected Choice chip |
| `Color.menu.selectedBorder` | Border on a selected Choice chip. **[V] Confirmed to diverge from `Color.accent`** under the probed theme — use `Color.menu.selectedBorder` for chips specifically; reserve `Color.accent` for Action-button fill, focus rings, and the active tab underline. |
| `Color.menu.scrim` | Backdrop behind an open dropdown, if the host renders one |
| `Color.accent` | Action-button fill, focus ring, active tab underline |
| `Color.urgent` | Conflict state (red tab badge, conflict row border, error text). **[V] Known bug:** passing `Color.urgent` as the *fallback* argument of `Border.surfaceSpec` never renders, because `shell.toml` always supplies a primary value (`popups.border`/`menu.border`) and the fallback is only used when the primary is absent. Conflict borders must be set directly, e.g. `Border.flat(Color.urgent, Style.normalBorderWidth)`, not passed as a fallback that will never be reached. |
| `Color.foreground` | Fallback text only where no `popups`/`menu`/`bar` token applies |
| `Color.bar.background`, `.text`, `.active` | Bar widget only (`S1`); there is no `Color.bar.foreground` — `Ui.WidgetButton.foreground` already resolves to the injected host's animated `bar.barForeground`, with `Color.bar.text` as the no-host fallback [V] |

**Dim/secondary text [V, host-precedented]:** the only approved way to produce dim or secondary text is `Qt.darker(<base token>, 1.4)`, confirmed as the host's own idiom in three separate components. This is direction-correct on both dark and light themes: it moves a light foreground toward gray on a dark theme, and moves a dark foreground further from a light background on a light theme. **Do not dim text by reducing opacity/alpha** (e.g. `Util.alpha(text, 0.55)`); alpha blending moves text *toward whatever is behind it*, which on a light theme walks a light-ish foreground toward the light background — the same class of white-on-white contrast bug this project already hit once on Catppuccin Latte.

Reject anything that computes color from `colors.toml` directly: Quickshell already resolves the active theme into these singletons and repaints them live. A second, Station-owned parsing and blending pipeline is redundant, untested, and a second place for a theme to render wrong.

## Typography

`Style.font.family` for every piece of text — never a literal font string, even though Omarchy's default is JetBrainsMono Nerd Font; the token is what stays correct if the user changes font with `omarchy font set`. Use `Style.font.*` size tokens for the whole type scale; `Style.font.bodySmall` and `Style.font.caption` are already in use in `Panel.qml` [V]. The full list from the installed `Style.qml` [V]: `caption` (10), `bodySmall` (11), `body` (12), `subtitle` (13), `title` (14), `heading` (16), `display` (24), `displayLarge` (28), plus glyph sizes `iconSmall`, `icon`, `iconLarge`, `iconFont`. There is no weight token in `Style.font` — emphasis is `Font.*` weight on top of a size token ([Components](components.md) already uses `Font.DemiBold`/`Font.Medium`) [V]. The panel itself needs only `caption`, `body` and `title`, all three already in use [V]; reuse before adding anything.

| Role | Token (confirm name) | Case | Use |
|---|---|---|---|
| Eyebrow / section label | `Style.font.caption`, dim | UPPERCASE | `LAYOUT` uses `Ui.PanelSectionHeader`; control row titles use `PanelUi.ControlLabel`. |
| Body | `Style.font.body` for control content; `Style.font.caption` for row titles, device names and fine print | Sentence | Dropdown values and control content |
| Body emphasis | `Font.DemiBold` at the same `Style.font.*` size — sizes only from `Style.font`, weight from `Font.*` [V] | Sentence | Values: `100%`, `1920×1080`, `60 Hz` |
| Caption | `Style.font.caption` | Sentence | Device names, "Lane 2", fine print |
| Panel title | `Style.font.title` + `Font.DemiBold` [V, in use] | Sentence | `Station` |

**Tabular figures [V]:** neither `Style.font` nor any host component exposes a tabular-figures property (the host never sets one), and the default family is monospace, so figures already align — set nothing. If a future theme ships a proportional family, alignment must come from a host token; do not hand-roll a width hack. [DECISION]
