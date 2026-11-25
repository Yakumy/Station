<!-- summary: The UI rules: no private palette, actions and choices, corners, elevation, spacing, do-not list, acceptance. Index of the design pages. -->
<!-- code: lib/**/*.qml -->
# Design system

For promotional artwork and the optional Station desktop theme, see the
[Station branding palette](branding.md). Runtime plugin UI continues to use
the selected Omarchy theme's tokens as specified here.

Tags: **[V]** confirmed in this codebase or in platform testing, **[VERIFY]** confirm the exact token against the installed `qs.Commons` and `qs.Ui`, **[DECISION]** a signed-off choice.

## Find the page

<!-- index design -->
| Read | For | Tokens |
| --- | --- | --- |
| [Components](design/components.md) | Tabs, chips, buttons, toggles, list rows, dropdowns, sliders, monitor cards: which to use and how each looks. | 1600 |
| [Layouts, frames and control rows](design/layouts.md) | Monitor rectangles and canvas framing, window preview, panel frame, shared control rows, portrait drawers. | 1600 |
| [Color and typography tokens](design/tokens.md) | Every color, border and type token Station may use, and its role. | 1700 |
<!-- /index -->

## The rule

**[DECISION] Station owns zero color or radius of its own.** Every value in this document is a token name or a rule, never a literal. A theme change must repaint every pixel with no restart, because the host already does this for every other panel.

**A comment explaining why a private color or radius constant is "necessary" is not an exception to this rule — it's a sign the component is missing from `qs.Ui`/`qs.Commons`.** Find the existing host component or get the author's sign-off to add one; don't derive a private token to paper over the gap. An audit of this codebase found exactly this pattern: a block of Station-owned radii and nine computed colors (`surfaceOne/Two/Three`, `accentMuted`, `accentHover` via `Qt.lighter`, dim-text variants, a halo radius), each justified by its own comment. All of it must be deleted and replaced with aliases to the [tokens](design/tokens.md#color-tokens), with the one exception noted there for dim text.

## Actions and choices

**[DECISION] Actions and choices are two components with two jobs, and they must look different:**

| Role | Used for | Selected look |
|---|---|---|
| **Action** | Keep, Revert, Pick another key, Replace and unbind it, Save | Filled: `Color.accent` background, `Color.popups.background` (or the theme's contrasting foreground) text. This is the *only* place a solid accent fill is allowed. |
| **Choice: chip group** (the 4 modifier-key toggles) | independently toggled key modifiers | `lib/panel/ChoiceChip.qml` wraps the host's `Ui.Button` choice chrome. Scale and Role no longer use chips in the approved larger-panel render: Scale is a notched slider, Role is a compact number menu in each monitor card. |
| **Choice: dropdown row** (Mode, Direction, monitor role) | one row selected inside an open list | The larger-panel render uses compact text triggers and host menu color tokens. Resolution and Refresh are now indexed sliders, not dropdowns. |

A Choice (either kind) must never use the Action look, and vice versa. The 4 modifier chips use `PanelUi.ChoiceChip`; Keep / Revert / Pick another key / Replace and unbind it / Apply stay `Ui.Button`s with exactly one filled commit action per screen.

## Corners

Joined button groups use square inner corners. Only the first button's left corners
and the last button's right corners use `Style.cornerRadius`; their shared corners
are explicitly zero. Workspace and Wallpaper mode selectors use dropdowns.

**[DECISION] Bind to `Style.cornerRadius` everywhere; never hardcode a radius, including `0`, except joined buttons’ shared corners and the monitor rectangles in the layout panels, which are always sharp.** Omarchy's current default resolves it sharp, which is what gives the panel its "sharp edges." Binding to the token rather than hardcoding zero means the panel still follows a theme that sets a different value, the same way every other token does. No component in this document uses a fixed pixel radius. Switch tracks and knobs also bind directly to the live corner token.

**Known trap [V]:** a ternary like `selected ? Station.radiusSm : Style.cornerRadius` *looks* compliant because the token appears in the source, but if the first branch is always taken, the token branch is dead code and never executes. The fix must remove the private branch entirely, not just add the token as an unreached fallback next to it.

## No elevation effects

**[DECISION] No `box-shadow`, no glow, no blur, no gradient, anywhere in Station**, including for selection and focus. Depth and emphasis come only from:
- a border (neutral control outline from `Border.controlSpec("normal", …)` — never `Color.popups.border`, which resolves to the accent, see [tokens](design/tokens.md#color-tokens) — `Color.accent` for selection/focus, `Color.urgent` for conflicts), and
- one step of fill (`Color.popups.background` → `Color.menu.selectedBackground` for a lifted/selected surface).

This matches `Style.cornerRadius`'s own flat language and is already the rule for the rest of the panel [V].

**App indicator treatment:** All icons display their original artwork in full color and at full opacity, regardless of focus. App slots are 102% of station-label ink height. In the kanji indicator style the guide is 十, so icon size stays steady while the numerals' own ink height changes. Images preserve aspect ratio and render directly, with oversampled physical-pixel decoding and mipmaps; no focus-based grayscale, opacity, scaling, or effect layer is applied. The drawer's shared reveal animation still fades its contents during opening and closing.

**One narrow, named exception [V, host-precedented, RESOLVED].** The ban in this section is on *elevation effects* specifically — not on the `QtQuick.Effects` import as a whole. A `MultiEffect` whose only properties set are `colorization`-related (tinting a monochrome icon, such as the Station logo, to match a theme token) is icon theming, not depth, and is allowed; Omarchy's own Tray widget does exactly this. A `MultiEffect` is still banned the moment it also sets any shadow/blur/glow-family property (`shadowEnabled`, `blurEnabled`, etc.) alongside colorization — **the exception covers a colorization-only instance, not any instance that merely includes colorization among other properties.** `DropShadow`, `Glow`, `Blur` and any gradient property remain banned outright, on any element, not just inside an `Effects` import.

An SVG used as the source of that colorization effect must be a fully opaque
white alpha mask. `MultiEffect` preserves source luminance during
colorization, so a beige or gray source silently darkens the requested theme
token even when `colorization` is 1.0.

## Spacing

`Style.space(n)` and `Style.spacing.*` only. The full named scale from the installed `Style.qml` [V]: steps `xxs` (2), `xs` (3), `sm` (4), `md` (6), `lg` (8), `xl` (10), `xxl` (12), `xxxl` (14), `huge` (18), plus `hairline` (`Style.space(1)`) and component aliases `controlGap`, `controlPaddingX/Y`, `inputPaddingY`, `controlHeight`, `popupRowHeight`, `dropdownWidth`, `searchableDropdownWidth`, `numberFieldWidth`, `searchablePopupMinHeight`, `rowGap`, `rowPaddingX`, `labelGap`, `panelGap`, `panelPadding`, `popupPadding`. Reuse these before adding new numeric calls. **Caveat from M0:** a requested `Style.space(680) × Style.space(560)` rendered as 567×467 logical pixels under the active theme and scale [V, [Panel findings](platform/panel.md#popout-structure)] — `Style.space(n)` is not 1:1 with logical pixels. Design to *relative* spacing (same step used consistently) rather than calibrating against an assumed pixel target.

Bar thickness is the exception that starts from the dedicated Omarchy tokens
`Style.bar.sizeHorizontal` and `Style.bar.sizeVertical`; Station's per-monitor
Height control may increase it, but never lowers it below the active token.
Primary Station bar controls use `Style.bar.iconSlot` along the bar axis and
zero inter-slot spacing, matching Omarchy's adjacent status controls in either
orientation. Do not derive a separate gap from `iconSlot` and `iconCanvas`.
Blurred bars use a nearly clear 1% mask derived from `Color.bar.background`
through `Util.alpha`; it activates compositor blur without adding a visible
dark glass tint or a separate palette. Bar appearance
choices use `ControlDropdown.qml`, Station's themed dropdown, at full row width and
`Style.spacing.controlHeight`.

Layout rhythm: section header → `Style.spacing.sm` (or the nearest named step) → control. Feature control panels share this rhythm. Settings and Keybindings use compact list rows.

## Do-not list

- No `box-shadow`, glow, blur or gradient, including for selection, focus or conflict states.
- No hardcoded radius, including `0` — use `Style.cornerRadius`, except the
  explicit Bar-tab Pill style whose island radius is half its shorter side, the
  monitor rectangles of the layout panels (`radius: 0`) and the Windows preview
  windows (Border roundness).
- No pill/`radius-full` shapes outside the explicit per-monitor bar Pill style.
- No solid accent fill on a Choice chip — that look is reserved for Action buttons.
- No border or fill decoration on a List row that isn't in a conflict state — this includes the real `Border.controlSpec("normal", …)` token now that one exists; it's for controls, not row containers (§4, §7).
- No literal hex, literal font family string, or literal pixel spacing/radius anywhere in runtime QML. `test/lint/theme-tokens.mjs` now enforces all of this [V, implemented]: it fails on a hex literal; a `radius:` not bound to `Style.cornerRadius`; `Qt.rgba(`; `Qt.lighter(`; derived-colour helpers except the approved `Qt.darker(<token>, 1.4)` dim idiom and the exact `Util.alpha(Commons.Color.bar.background, 0.01)` Blur mask; any gradient property; actual `DropShadow`/`Glow`/`Blur` QML effect declarations (semantic strings such as the compositor-owned `"blur"` mode are allowed); any `shadow…` property; and `MultiEffect` **except** an instance whose complete property set is colorization-only ([elevation](#no-elevation-effects)) — colorization alongside `shadowEnabled` fails both the property-set test and the shadow test. Comment lines are stripped before matching, so prose may mention a banned token.

## Acceptance

A change passes when, under at least two themes including one light theme (Catppuccin Latte already found a white-on-white contrast bug once — re-check it specifically [V, earlier Latte finding]):
- Scale, Resolution, and Refresh show valid notched choices; monitor role menus show the enabled role numbers; Keep remains visually heavier than these choices.
- Keep/Revert/Replace are the only filled, high-emphasis controls on the page — i.e. exactly one filled commit Action per screen (`Keep`, `Apply`, `Replace and unbind it`), no filled Choice anywhere.
- Keybindings and Settings rows read as a plain hairline list; the only bordered row is one with an active conflict.
- No rounded corners, shadows or glows appear anywhere, at any theme.
- Every color, font and spacing value traces to a token in [Tokens](design/tokens.md) or [Spacing](#spacing), with no literal left in the diff.
