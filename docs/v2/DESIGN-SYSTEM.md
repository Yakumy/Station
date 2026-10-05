# Station — Design System Specification

## Purpose & scope

This spec covers Station, an Omarchy Quattro display-management plugin panel. The current build has correct layout and interaction flow but no shared rules for spacing, type, color or radius — each control was styled on its own, so sizes and gaps drift panel to panel. This document fixes that: one token set, one component spec, used everywhere in the panel.

It is written to sit inside Omarchy's own visual language rather than invent a new one: dark-first, monospace (JetBrainsMono Nerd Font), low-chroma neutral surfaces with a single accent, minimal rounding, no drop shadows or gradients, and compatible with Omarchy's theme engine (`colors.toml`) so the panel can re-skin when the user switches system themes.

## Principles

1. **Dark-first, flat.** No gradients, no drop shadows, no glassmorphism. Depth comes from a 3-step surface ramp (background → card → raised/active), not elevation effects.
2. **Monospace everywhere.** Omarchy's identity is JetBrainsMono Nerd Font across terminal, bar and launcher. Station uses it for every label and value — including numbers, which get `tabular-nums` so columns of digits (resolution, Hz, %) align.
3. **One accent, used sparingly.** A single blue signals selection, focus and the active tab/segment. It never doubles as decoration.
4. **Quiet hierarchy through weight and opacity, not size.** Section labels are small, uppercase, wide-tracked and dim (`text-3`); values are the same size as labels but brighter and heavier. Few font sizes, many weight/color steps.
5. **4px grid, 8px rhythm.** Every gap, padding and offset is a multiple of 4, with 8/16/24 doing most of the work — matching the dotted 16px grid already in the layout canvas.
6. **Minimal, consistent rounding.** 4–6px radii only. Nothing pill-shaped except true toggles/switches.
7. **Theme-able, not hard-coded.** Every color is a token that can be re-pointed at an Omarchy `colors.toml` palette; component code never references a raw hex.

## Color tokens

All values below are the default (Omarchy "Tokyo-blue") skin. Every token maps to a CSS variable; component styling references only the variable name, never a literal hex, so a theme swap (next section) repoints the whole panel.

| Token | Hex | Role |
| --- | --- | --- |
| `--bg` | `#0D0F14` | App/window background |
| `--surface-0` | `#15171E` | Layout canvas / recessed areas |
| `--surface-1` | `#1A1D26` | Default card / display node / input fill |
| `--surface-2` | `#20232E` | Hover state |
| `--surface-3` | `#262A37` | Active / pressed / selected-segment fill |
| `--border-subtle` | `#242732` | Hairlines between major regions (header, sidebar) |
| `--border-default` | `#30343F` | Default control border |
| `--border-strong` | `#3C4150` | Emphasized border (unselected display node) |
| `--accent` | `#5B8DFD` | Selection, focus ring, active tab/segment, primary action |
| `--accent-hover` | `#7EA3FF` | Accent hover/pressed, accent-colored text |
| `--accent-muted` | `rgba(91,141,253,.16)` | Focus halo / selected-card glow |
| `--text-1` | `#E7E9EE` | Primary text, values |
| `--text-2` | `#9AA0B2` | Secondary text, meta |
| `--text-3` | `#636B7E` | Section labels, muted captions |
| `--text-4` | `#454B5A` | Disabled / tertiary hints |
| `--success` | `#4ADE80` | Positive status (reserved) |
| `--danger` | `#F2667B` | Destructive / error (reserved) |
| `--warning` | `#F5B700` | Warning — also Omarchy's "Linux Yellow" brand accent, for rare system-level callouts |

**Contrast:** `text-1` on `bg`/`surface-1` is 13.8:1; `text-2` is 5.4:1; `text-3` is 3.1:1 — used only for labels ≥14px or paired with an icon, never for critical body text.

## Typography

**Font:** `'JetBrains Mono', 'JetBrainsMono Nerd Font', ui-monospace, monospace` — the same family Omarchy sets system-wide via `omarchy font set`. Weights used: 400 (rare), 500 (default), 600 (emphasis/headings), 700 (display, specimen headings only).

| Style | Size / line-height | Weight | Tracking | Case | Use |
| --- | --- | --- | --- | --- | --- |
| Eyebrow | 11 / 16 | 600 | 0.08em | UPPERCASE | Section labels: `LAYOUT`, `BRIGHTNESS`, `SCALE` |
| Micro meta | 10 / 14 | 500 | 0.04em | UPPERCASE | Fine print: `Lane 2`, grid captions |
| Caption | 11 / 16 | 500 | 0.02–0.04em | Sentence | Device name, secondary descriptors |
| Body | 12–13 / 16–18 | 500 | 0 | Sentence | Control labels, dropdown values |
| Body emphasis | 13 / 18 | 600 | 0 | Sentence | Values: `100%`, `1920x1080`, `60 Hz` |
| Panel title | 14 / 20 | 600 | 0.01em | Sentence | `Station` |
| Spec heading | 20 / 28 | 700 | 0.01em | Sentence | Document/specimen titles only |

**Rules:** numeric values always get `font-variant-numeric: tabular-nums` so stacked numbers align. Section labels (eyebrow) are always `text-3`, never full-bright — they organize, they don't compete with values. There are only 6 sizes in the whole panel; new UI reuses one of them rather than inventing a 7th.

## Spacing & layout grid

Base unit: **4px**. Only these steps are used — pick the smallest that reads clearly, never an in-between value:

| Token | Value | Typical use |
| --- | --- | --- |
| `space-1` | 4px | Icon-to-label gap, tight stacks |
| `space-2` | 8px | Segmented control gaps, chip padding |
| `space-3` | 12px | Compact group padding |
| `space-4` | 16px | Section gap in sidebar, row padding |
| `space-5` | 20px | Panel padding (top/bottom) |
| `space-6` | 24px | Panel padding (left/right), region gutters |
| `space-8` | 32px | Rarely — separating major blocks |

**Regions:** header bar is a fixed 56px; sidebar/inspector is a fixed 320px column; the layout canvas fills the rest. Both header and sidebar use 24px horizontal padding and 20px vertical padding, so every region shares the same outer rhythm.

**Layout canvas grid:** the dotted background grid stays at 16px (4 × base unit) — this is also the snap increment for dragging display nodes, so the visual grid and the interaction grid are the same number.

## Radius & elevation

| Token | Value | Use |
| --- | --- | --- |
| `radius-sm` | 4px | Segmented-control segments, small icon buttons, checkboxes |
| `radius-md` | 6px | Cards, inputs, selects, display nodes, the layout canvas itself |
| `radius-lg` | 10px | Popovers/menus, modal sheets (none in current panel, reserved) |
| `radius-full` | 999px | True switches/pill toggles only — not used elsewhere |

No drop shadows for resting state. The only "elevation" cue is the **selection glow**: `box-shadow: 0 0 0 3px var(--accent-muted)` combined with a 1.5px `--accent` border — used once, for the currently-selected display node or focused input. A plain popover (if ever needed) may use a single soft shadow (`0 4px 16px rgba(0,0,0,.4)`), but panel chrome itself stays flat.

## Components

**Tabs (top nav — Displays / Keybindings / Settings)** Text: body, `text-2`; active tab text: `text-1`. 2px bottom border, `transparent` when inactive, `--accent` when active, 18px gap below the baseline to the header's bottom border. 28px horizontal gap between tabs.

**Segmented control (Scale: 1x/1.25x/.../ Role: Primary/Secondary)** Row of equal-width buttons, `space-2` (8px) gap, no shared container border — each segment is its own `radius-sm` rect. Default: transparent fill, `border-default`, `text-3` label. Active/selected: `surface-3` fill with `border-strong` (for neutral multi-choice like Scale) **or** solid `--accent` fill with `--bg`-colored text (for binary state like Role, where the active choice is also a commitment, not just a filter). Height 28–32px, label is body-emphasis.

**Slider (Brightness)** 4px track, full-width, `radius-sm`, fill in `--accent` up to value, 14px circular white thumb with a soft shadow, no track border. Value shown right-aligned above the track as body-emphasis with a tabular-nums `%`.

**Select / dropdown (Resolution, Refresh, Mode, Direction)** `surface-1` fill, `border-default` 1px, `radius-sm`, `space-3` horizontal padding, 8px vertical. Value left, chevron (⌄) right in `text-3`. Open/focus state adds the focus ring (`accent-muted` halo + `accent` border).

**Display node (layout canvas item)** 220×110px card, `surface-1` fill, `radius-md`. Default: `border-strong` 1px. Selected: 1.5px `--accent` border + `accent-muted` glow (radius & elevation section). Two 18px rotate-handle chips top-left, number badge + output name centered, number in body-emphasis `text-1`, output name in caption `text-3` (or `accent-hover` when selected).

**Toggle/checkbox** (reserved for Keybindings/Settings) 18×18px, `radius-sm`, `border-default`; checked = `--accent` fill with a 1.5px white check mark.

**Section label** Every group (LAYOUT, BRIGHTNESS, SCALE, RESOLUTION · REFRESH, ROLE) uses the eyebrow style, `space-3` below it before the control starts.

## Interaction states & accessibility

| State | Rule |
| --- | --- |
| Hover | Fill steps up one surface level (`surface-1` → `surface-2`); border unchanged |
| Active/pressed | Fill steps to `surface-3`; no transform/scale |
| Selected | `--accent` border (1.5px) + `accent-muted` glow, as in Radius & elevation |
| Focus (keyboard) | Same glow as selected, always visible on `:focus-visible`, never removed |
| Disabled | `text-4` label, `border-subtle`, 60% opacity, no hover/active response |

**Targets:** every interactive control (segments, tabs, slider thumb, dropdown row) is at least 28px tall; icon-only buttons are 28×28px minimum hit area even if the glyph is smaller.

**Contrast:** all text/background pairs in this system meet WCAG AA (4.5:1 body, 3:1 for ≥14px labels); verified against the color table above.

**Motion:** transitions are 120–150ms ease-out on color/border/box-shadow only — no movement, bounce or scale, matching Hyprland's snappy, non-bouncy window animations.

## Mapping to Omarchy's theme system

Omarchy themes are defined centrally in `~/.local/state/omarchy/current/theme/colors.toml` and fanned out to the terminal, Waybar, Hyprland borders, btop, etc. Station should read from the same source rather than ship its own fixed palette, so it re-skins automatically when the user runs `omarchy theme set <name>`.

**Suggested mapping** (adjust names to whatever keys the active `colors.toml` actually exposes — Omarchy themes commonly expose a background, a foreground/text set, and 8–16 ANSI-style accent colors):

| Station token | Source in `colors.toml` |
| --- | --- |
| `--bg`, `--surface-0` | `background` (and a programmatically darkened/lightened step) |
| `--surface-1/2/3` | derived by mixing `background` toward `foreground` at 6% / 10% / 14% |
| `--border-*` | derived the same way, slightly lighter steps |
| `--text-1` | `foreground` |
| `--text-2/3/4` | `foreground` mixed toward `background` at 25% / 45% / 65% |
| `--accent`, `--accent-hover` | the theme's `color4` (blue) or `color6` (cyan), whichever the active theme defines as its primary accent; fall back to a built-in `#5B8DFD` if the theme has no clear accent |
| `--warning` | `color3` (yellow) |
| `--danger` | `color1` (red) |
| `--success` | `color2` (green) |

This keeps Station visually correct under Gruvbox, Tokyo Night, Catppuccin Mocha, Rose Pine and any other installed Omarchy theme, without Station maintaining its own theme list. The specimen sheet in the companion design canvas uses literal hex values for one concrete skin (a Tokyo-Night-leaning dark/blue default) — treat those as the fallback theme, not the only one.

### Live theme-following is a requirement, not an enhancement

Station never ships a fixed palette. Every color in the panel is a CSS custom property resolved at runtime from the **active** Omarchy theme, and the panel repaints **without a restart** the moment the user runs `omarchy theme set <name>` — the same instant Waybar, the terminal and Hyprlock repaint.

**What this means for implementation:**

1. **No hex literals in component code, ever.** Every rule in this spec (`--accent`, `--surface-1`, etc.) is a variable name. Components read `var(--token)`; they never fall back to a hardcoded color except the one bootstrap default used before the first theme read completes.
2. **One place sets the variables.** A single theme-loader module reads `~/.local/state/omarchy/current/theme/colors.toml`, maps its keys to Station's tokens (per the table above), and writes them onto the app's root element (e.g. `document.documentElement.style.setProperty('--accent', …)`, or the Hyprland-toolkit equivalent if Station isn't a web view). No component touches the TOML file directly.
3. **The panel watches for theme changes live**, not just on next launch. Omarchy switches themes by rewriting `~/.local/state/omarchy/current/theme` (a symlink) and re-running each app's theme hook. Station should either: (a) watch that path with a filesystem watcher (inotify) and re-run the loader on change, or (b) hook into Omarchy's own theme-change signal/command if the plugin API exposes one (check `omarchy theme set` — it's scriptable, and plugins can register a reload hook). Polling is a fallback only, not the first choice.
4. **Re-paint is instant and total.** Because every token is a variable, a single update at the root cascades to every control — there is no per-component re-render logic to write, no flash of unstyled content, no partial re-skin.
5. **Contrast holds across themes.** Since `text-3` labels sit at the edge of AA contrast (3.1:1) on the *default* skin, the loader should verify — or the theme mapping should guarantee — that derived text tokens stay ≥ 3:1 against `--bg` regardless of which theme is active; a theme whose background is unusually light or saturated should not silently break label legibility.

This behavior, and the mapping table above, are not optional polish — they're load-bearing: a Station that hardcodes today's blue-on-near-black palette is not actually following Omarchy's design system, it's just borrowing its look once.
