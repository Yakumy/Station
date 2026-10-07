# Station — Design System (v2)

Supersedes the earlier draft in this repo. Tags: **[V]** confirmed in this codebase or in M0 testing, **[VERIFY]** Codex must confirm the exact token/name against the installed `qs.Commons`/`qs.Ui` before relying on it, **[DECISION]** a rule, not a fact.

## 0. Why this version exists

The previous draft specified its own hex palette, its own `colors.toml` blending pipeline, 4–10px rounded corners, and drop-shadow/glow selection halos. None of that matches Omarchy, which M0 already proved exposes live-updating QML singletons (`Color.popups.*`, `Color.menu.*`, `Color.bar.*`, `Color.foreground`, `Color.accent`, `Color.urgent`) and a sharp-cornered, flat, hairline-separated visual language with no shadows or glows [V, §8.6 and §8.5 of `PLATFORM-FINDINGS.md`]. Station must look like it ships with Omarchy, not like a themed web app bolted onto it.

**[DECISION] Station owns zero color or radius of its own.** Every value in this document is a token name or a rule, never a literal. A theme change must repaint every pixel with no restart, because the host already does this for every other panel.

**A comment explaining why a private color or radius constant is "necessary" is not an exception to this rule — it's a sign the component is missing from `qs.Ui`/`qs.Commons`.** Find the existing host component or get the author's sign-off to add one; don't derive a private token to paper over the gap. An audit of this codebase found exactly this pattern: a block of Station-owned radii and nine computed colors (`surfaceOne/Two/Three`, `accentMuted`, `accentHover` via `Qt.lighter`, dim-text variants, a halo radius), each justified by its own comment. All of it must be deleted and replaced with aliases to the tokens in §4, with the one exception noted there for dim text.

## 1. The bug this document fixes

`Panel.qml` calls the exact same `Ui.Button { selected: … }` for Scale, Role, **and** Keep/Revert/Replace. That component renders `selected: true` as a strong, filled, high-emphasis state — correct for a button that commits an action, wrong for a chip that is just one of several peers. The result: **Primary** (merely a choice) looks identical in weight to **Keep** (an action with consequences), and **Secondary** looks like a disabled or unimportant option next to it, when really both are just unselected peers.

**[DECISION] These are two different components with two different jobs, and the system must give them two different looks:**

| Role | Used for | Selected look |
|---|---|---|
| **Action** | Keep, Revert, Pick another key, Replace and unbind it, Save | Filled: `Color.accent` background, `Color.popups.background` (or the theme's contrasting foreground) text. This is the *only* place a solid accent fill is allowed. |
| **Choice: chip group** (the 4 modifier-key toggles) | independently toggled key modifiers | `Station/ChoiceChip.qml` wraps the host's `Ui.Button` choice chrome. Scale and Role no longer use chips in the approved larger-panel render: Scale is a notched slider, Role is a compact number menu in each monitor card. |
| **Choice: dropdown row** (Mode, Direction, monitor role) | one row selected inside an open list | The larger-panel render uses compact text triggers and host menu color tokens. Resolution and Refresh are now indexed sliders, not dropdowns. |

A Choice (either kind) must never use the Action look, and vice versa. The 4 modifier chips use `Station/ChoiceChip`; Keep / Revert / Pick another key / Replace and unbind it / Apply stay `Ui.Button`s with exactly one filled commit action per screen.

## 2. Corners

**[DECISION] Bind to `Style.cornerRadius` everywhere; never hardcode a radius, including `0`.** Omarchy's current default resolves it sharp, which is what gives the panel its "sharp edges." Binding to the token rather than hardcoding zero means the panel still follows a theme that sets a different value, the same way every other token does. No component in this document uses a fixed pixel radius, and nothing is pill-shaped.

**Known trap [V]:** a ternary like `selected ? Station.radiusSm : Style.cornerRadius` *looks* compliant because the token appears in the source, but if the first branch is always taken, the token branch is dead code and never executes. The fix must remove the private branch entirely, not just add the token as an unreached fallback next to it.

## 3. No elevation effects

**[DECISION] No `box-shadow`, no glow, no blur, no gradient, anywhere in Station**, including for selection and focus. Depth and emphasis come only from:
- a border (neutral control outline from `Border.controlSpec("normal", …)` — never `Color.popups.border`, which resolves to the accent, §4 — `Color.accent` for selection/focus, `Color.urgent` for conflicts), and
- one step of fill (`Color.popups.background` → `Color.menu.selectedBackground` for a lifted/selected surface).

This matches `Style.cornerRadius`'s own flat language and is already the rule for the rest of the panel [V, STATION-V2-SPEC.md §11].

**One narrow, named exception [V, host-precedented, RESOLVED].** The ban in this section is on *elevation effects* specifically — not on the `QtQuick.Effects` import as a whole. A `MultiEffect` whose only properties set are `colorization`-related (tinting a monochrome icon, such as the Station logo, to match a theme token) is icon theming, not depth, and is allowed; Omarchy's own Tray widget does exactly this. A `MultiEffect` is still banned the moment it also sets any shadow/blur/glow-family property (`shadowEnabled`, `blurEnabled`, etc.) alongside colorization — **the exception covers a colorization-only instance, not any instance that merely includes colorization among other properties.** `DropShadow`, `Glow`, `Blur` and any gradient property remain banned outright, on any element, not just inside an `Effects` import.

## 4. Color tokens

No hex literals anywhere in Station. Every color is one of these, confirmed present in the installed `qs.Commons` [V, `PLATFORM-FINDINGS.md` §8.6]:

| Token | Role |
|---|---|
| `Color.popups.background` | Panel background |
| `Color.popups.text` | Default text |
| `Color.popups.border` | **Not a neutral border on the default theme** [V]. Omarchy's generated `shell.toml` maps `[popups] border` to the active-window-border color, i.e. the accent. Using it for a plain row or card border produces an unintended accent-blue box — this is exactly the "every row is bordered blue" bug found in this codebase. Never use it as a neutral border. |
| **Neutral row separator** | `Ui.PanelSeparator` [V] — the host's own hairline, drawn at a reduced-opacity foreground. This is the only correct way to separate rows with no box. |
| **Neutral control border** | `Border.controlSpec("normal", …)` [V, RESOLVED] — resolves to foreground at ~40% opacity, 1px. This is already what `Ui.Button { bordered: true }` and `Ui.Dropdown` paint by default, so using it for chip groups, display nodes and secondary actions makes them match controls Omarchy already ships, rather than inventing a fourth border weight. **Scope: this is for actual controls (buttons, dropdowns, chip groups, display nodes) — never for a List row container.** A List row stays fully borderless per §7, even now that a real neutral-border token exists; giving every row this border would recreate "every row is boxed," just in gray instead of blue. Use this, not `Color.popups.border`, anywhere a control needs an outline. |
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
| `Color.bar.background`, `.text`, `.active` | Bar widget only (`[S n]`); there is no `Color.bar.foreground` — use the injected widget-host `bar.foreground` where available, else `Color.bar.text` [V] |

**Dim/secondary text [V, host-precedented]:** the only approved way to produce dim or secondary text is `Qt.darker(<base token>, 1.4)`, confirmed as the host's own idiom in three separate components. This is direction-correct on both dark and light themes: it moves a light foreground toward gray on a dark theme, and moves a dark foreground further from a light background on a light theme. **Do not dim text by reducing opacity/alpha** (e.g. `Util.alpha(text, 0.55)`); alpha blending moves text *toward whatever is behind it*, which on a light theme walks a light-ish foreground toward the light background — the same class of white-on-white contrast bug this project already hit once on Catppuccin Latte.

Reject anything that computes color from `colors.toml` directly: Quickshell already resolves the active theme into these singletons and repaints them live. A second, Station-owned parsing and blending pipeline is redundant, untested, and a second place for a theme to render wrong.

## 5. Typography

`Style.font.family` for every piece of text — never a literal font string, even though Omarchy's default is JetBrainsMono Nerd Font; the token is what stays correct if the user changes font with `omarchy font set`. Use `Style.font.*` size tokens for the whole type scale; `Style.font.bodySmall` and `Style.font.caption` are already in use in `Panel.qml` [V]. The full list from the installed `Style.qml` [V]: `caption` (10), `bodySmall` (11), `body` (12), `subtitle` (13), `title` (14), `heading` (16), `display` (24), `displayLarge` (28), plus glyph sizes `iconSmall`, `icon`, `iconLarge`, `iconFont`. There is no weight token in `Style.font` — emphasis is `Font.*` weight on top of a size token (§7 already uses `Font.DemiBold`/`Font.Medium`) [V]. The panel itself needs only `caption`, `body` and `title`, all three already in use [V]; reuse before adding anything.

| Role | Token (confirm name) | Case | Use |
|---|---|---|---|
| Eyebrow / section label | smallest available, dim | UPPERCASE | `LAYOUT`, `BRIGHTNESS`, `SCALE` — already `Ui.PanelSectionHeader` |
| Body | `Style.font.body` (12) for row labels and values, `Style.font.caption` (10) for device names and fine print [V, in use] | Sentence | Row labels, dropdown values |
| Body emphasis | `Font.DemiBold` at the same `Style.font.*` size — sizes only from `Style.font`, weight from `Font.*` [V] | Sentence | Values: `100%`, `1920×1080`, `60 Hz` |
| Caption | `Style.font.caption` | Sentence | Device names, "Lane 2", fine print |
| Panel title | `Style.font.title` + `Font.DemiBold` [V, in use] | Sentence | `Station` |

**Tabular figures [V]:** neither `Style.font` nor any host component exposes a tabular-figures property (the host never sets one), and the default family is monospace, so figures already align — set nothing. If a future theme ships a proportional family, alignment must come from a host token; do not hand-roll a width hack. [DECISION]

## 6. Spacing

`Style.space(n)` and `Style.spacing.*` only. The full named scale from the installed `Style.qml` [V]: steps `xxs` (2), `xs` (3), `sm` (4), `md` (6), `lg` (8), `xl` (10), `xxl` (12), `xxxl` (14), `huge` (18), plus `hairline` (`Style.space(1)`) and component aliases `controlGap`, `controlPaddingX/Y`, `inputPaddingY`, `controlHeight`, `popupRowHeight`, `dropdownWidth`, `searchableDropdownWidth`, `numberFieldWidth`, `searchablePopupMinHeight`, `rowGap`, `rowPaddingX`, `labelGap`, `panelGap`, `panelPadding`, `popupPadding`. Reuse these before adding new numeric calls. **Caveat from M0:** a requested `Style.space(680) × Style.space(560)` rendered as 567×467 logical pixels under the active theme and scale [V, `PLATFORM-FINDINGS.md` §8.5] — `Style.space(n)` is not 1:1 with logical pixels. Design to *relative* spacing (same step used consistently) rather than calibrating against an assumed pixel target.

Layout rhythm: section header → `Style.spacing.sm` (or the nearest named step) → control. One shared vertical rhythm between the Displays sidebar, Keybindings rows and Settings rows, so switching tabs doesn't change the page's density.

## 7. Component inventory

Reuse what's already confirmed working before adding anything: `Ui.Panel`, `BarIconButton`, `KeyboardPanel`, `PanelKeyCatcher`, `ScrollView`, `PanelSectionHeader`, `PanelSeparator`, `Ui.Button`, `Ui.TextField` [V, `Panel.qml`].

**Tabs** (Displays / Keybindings / Settings): `Color.popups.text` inactive, `Color.popups.text` at full opacity + `Color.accent` 2px bottom border active. No fill change, no box.

**Choice chip** (the 4 modifier-key toggles): see §1. Displays uses sliders and compact text menus instead.

**Action button** (Keep, Revert, Pick another key, Replace and unbind it): see §1. A destructive or replace-type action may use `Color.urgent` as its fill instead of `Color.accent`, same shape.

**Toggle** (Settings: Hide indicator, Follow focus): **[V] Resolved — `Ui.Toggle` exists and Settings already uses it correctly.** No further action needed here; do not replace it with a chip or anything else.

**[DECISION, signed off] Secondary vs. primary Action.** §1 says every Action is filled, but a screen can have more than one Action at once (Keep + Revert; Pick another key + Replace and unbind it), and making both equally heavy loses the sense of which one actually commits. Settled rule: the *one* action that commits a consequential change (Keep; Apply; Replace and unbind it) is filled per §1; a same-row action that only cancels or defers (Revert; Pick another key) is neutral-bordered — `Border.controlSpec("normal", …)` border, `Color.popups.text`, no fill — so the eye finds the committing action first. This is now final: one filled commit Action per screen, its cancel/defer partner neutral.

**List row** (Keybindings action rows, Settings rows): **[DECISION] default = no border, no individual box.** Rows are separated only by `Ui.PanelSeparator` (a hairline), with shared left/right padding, the way `Ui.PanelSectionHeader` already separates sections. A row gets a `Color.urgent` border **only** while it is an unresolved conflict — that is the one state worth decorating, and decorating every row equally erases it. A row never gets an accent border just for existing; accent belongs to the interactive control inside the row (a focused dropdown, an open menu), not the row container.

**Select / dropdown** (Mode, Direction, monitor role): the approved render puts compact borderless triggers in the top tab row and inside the monitor cards. `Station/InlineDropdown.qml` keeps the text and chevron content-sized, uses host menu tokens for the popup, and right-aligns Mode's wider menu so named Single-output choices stay readable within the panel.

**Slider** (Brightness, Text size, Scale, Resolution, Refresh): host-owned `Ui.PanelSlider` paints the track and knob. The last four use discrete index stops (`tickCount`); no slider may interpolate unsupported display modes. Changes to display geometry preview on release, not on every drag position. No glow or thumb shadow.

**Display node** (Layout canvas): default `Border.controlSpec("normal", Color.popups.text, Color.accent)` at `Style.cornerRadius` [V] (never `Color.popups.border`); selected `Color.accent` border (≥2× `Style.normalBorderWidth`) with `Color.menu.selectedBackground` fill — border + one fill step, no glow, confirming the earlier transparency bug stays fixed (no `opacity` reduction on selection; `opacity` is reserved for *disabled*, not *selected*).

## 8. Do-not list

- No `box-shadow`, glow, blur or gradient, including for selection, focus or conflict states.
- No hardcoded radius, including `0` — always `Style.cornerRadius`.
- No pill/`radius-full` shapes.
- No solid accent fill on a Choice chip — that look is reserved for Action buttons.
- No border or fill decoration on a List row that isn't in a conflict state — this includes the real `Border.controlSpec("normal", …)` token now that one exists; it's for controls, not row containers (§4, §7).
- No literal hex, literal font family string, or literal pixel spacing/radius anywhere in `Panel.qml`, `Service.qml`, or any component file. `tools/v2/check-theme-tokens.mjs` now enforces all of this [V, implemented]: it fails on a hex literal; a `radius:` not bound to `Style.cornerRadius`; `Qt.rgba(`; `Qt.lighter(`; any derived-colour helper other than the approved `Qt.darker(<token>, 1.4)` dim idiom (so `Util.alpha(`, `Qt.tint(` and any other `Qt.darker(` arity fail); any gradient property; any `DropShadow`/`Glow`/`Blur`-family identifier; any `shadow…` property; and `MultiEffect` **except** an instance whose complete property set is colorization-only (§3) — colorization alongside `shadowEnabled` fails both the property-set test and the shadow test. Comment lines are stripped before matching, so prose may mention a banned token.

## 10. Functional bugs found during audit (fix with priority — not cosmetic)

**[V] Both fixed in this revision** (§8 CI now guards the token choices, so they cannot regress):

1. **Conflict rows never render red.** See the `Color.urgent` entry in §4: the fallback argument of `Border.surfaceSpec` is masked by a primary value `shell.toml` always supplies. A user got no visual warning that a keybinding they were about to apply conflicted with an existing one. Fix directly (`Border.flat(Color.urgent, Style.normalBorderWidth)`), don't pass it as an unreachable fallback.
2. Every Settings/Keybindings row rendered with an accent-blue border because it was built from `Color.popups.border`, which is not neutral (§4). Fixing the token choice (to `Ui.PanelSeparator` / `Border.controlSpec("normal", …)`) fixes this as a side effect of §4, not a separate task.

## 9. Acceptance

A change passes when, under at least two themes including one light theme (Catppuccin Latte already found a white-on-white contrast bug once — re-check it specifically [V, earlier Latte finding]):
- Scale, Resolution, and Refresh show valid notched choices; monitor role menus show the enabled role numbers; Keep remains visually heavier than these choices.
- Keep/Revert/Replace are the only filled, high-emphasis controls on the page — i.e. exactly one filled commit Action per screen (`Keep`, `Apply`, `Replace and unbind it`), no filled Choice anywhere.
- Keybindings and Settings rows read as a plain hairline list; the only bordered row is one with an active conflict.
- No rounded corners, shadows or glows appear anywhere, at any theme.
- Every color, font and spacing value traces to a token in §4–§6, with no literal left in the diff.
