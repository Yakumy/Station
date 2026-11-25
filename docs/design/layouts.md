<!-- summary: Monitor rectangles and canvas framing, window preview, panel frame, shared control rows, portrait drawers. -->
<!-- code: lib/panel/** lib/**/*Layout.qml lib/**/*Tab.qml -->
# Layouts, frames and control rows

## Monitor canvas framing

**Monitor-canvas framing** (Displays / Bar / Wallpaper): fit the actual monitor
union proportionally inside the central 80% of the canvas, giving a default 10%
inset on the constraining width or height. Center the other dimension, whose
whitespace may therefore be larger. Do not reserve hypothetical disconnected
arrangements or cap the fit below the available canvas. Inset each painted
monitor card by half of `Style.spacing.sm`, producing a compact named gap
between touching monitors in Displays, Bar, and non-Span Wallpaper previews.
Span keeps exact edge-to-edge cards because its image crop is continuous. A non-Span
Wallpaper card keeps its monitor's exact shape, so it previews the desktop's crop.

## Bar edge geometry

**Bar edge geometry:** A bar with a visible surface (Pill in every background, and Omarchy
default in Solid or Blur) floats `Style.space(8)` from the monitor edge and from the ends
of its span, so it never touches the monitor. A Transparent Omarchy default bar is
edge-aligned. The surface reserves that space with the bar thickness, and Pill's islands
keep their internal padding. Window gaps do not move the bar.

## Layout monitor rectangles

The monitor rectangles in all six layout panels (Displays, Workspaces, Bar, Windows, Color Match, Wallpaper)
use a fixed sharp radius of 0 and never follow the theme rounding.

## Window geometry preview

The simulated windows in WindowsLayout are an exception to the corner token rule: their
radius is the Border roundness value in preview pixels, unscaled, so it stays visible at
preview zoom and follows the slider while it drags. Every simulated window is active:
accent border and the selected fill. All other surrounding chrome continues to use
`Style.cornerRadius`. Monitor names stay centered above the Windows animation.

## Panel frame

Use one tab-independent request of `Style.space(996)` by `Style.space(620)`
(content size before the host's border inset), fitted to the current screen.
The header and tab row stay fixed above a shared vertical overflow viewport.
Short tabs leave unused space; expanded notices and binding editors scroll
inside that frame. Scrollbars appear only on overflow. This replaces the earlier
content-driven height; theme/font and screen changes can still refit the frame.

## Shared control-panel rows

Displays is the reference for all feature controls. `ControlLabel.qml` places a
plain-text, uppercase caption at `Style.space(8)` from the top and left, using the
same dim popup foreground as Displays. Values align to the top right; hints align
to the bottom left with the same horizontal inset and `Style.space(4)` below.
Five-row control frames divide their height equally.

`ControlFrame.qml` restores the control width multiplier `1.2 * 0.96`, before
commit `ea956ed` narrowed it on 2026-11-12. The column split stays fixed and the
frame is centered and capped to the column with a `Style.space(8)` inset on each
side when the previous formula would overflow. Sliders, dropdowns and row buttons
share one inset at each end: `Style.space(8)` plus 0.5% of the remaining row width,
rounded up to a whole pixel. They are placed by `x`, not centered, because centering
rounds to a pixel and could pull a control up to a pixel left. Call sites never
re-center them. Sliders retain the host's half-knob track inset, keeping both endpoint
knobs and their hover enlargement inside the frame and clear of the row title, even at
a small font size, where the host holds the knob at 14 px while spacing shrinks.
`ControlButton.qml` provides the neutral row action style.

`ActionButton.qml` keeps the host control height and uses 99% of the original action
width. Apply, Cancel, Keep and Revert retain their additional 60% width factor.
Settings and Keybindings retain their compact hairline list
rows: vertically centered body labels, Settings values at the right, and centered
semibold binding combinations. They do not use the feature control-panel titles.
Settings' compact position dropdown is `Style.space(130) * 0.99` wide.

All six layouts show plain-text, dim monitor names centered inside each monitor,
using `MonitorName.qml`. Displays centers `name | role`, with the role remaining a
dropdown. Workspaces centers the same identity as read-only text. Bar centers the
switch below the name. Workspace badges occupy the upper half, Color Match status sits
below the name, and Windows names render above its animation. Wallpaper tiles
retain their exact monitor aspect ratio in every mode.
Bar monitor switches use a `Style.space(32)` by `Style.space(18)` track with a
`Style.space(14)` knob; Settings keeps the standard switch dimensions. In Bar portrait
both draw at 70% through `ToggleSwitch.sizeFactor`, rounded to whole units. Both follow
the live roundness token.

FeatureGeometry owns the feature tabs’ equal 370-unit frame heights. In Bar portrait
mode the divider has 36 units to each visible frame, and bottom padding is 36 units.
The control heading occupies part of the lower half of the gap. Portrait action drawers center their buttons and put any message under them in `Style.font.caption`. Screen fitting
bounds the content viewport and enables scrolling so bottom padding remains reachable.

Portrait action drawers use the full inter-frame gap (72 scaled units, twice the
36-unit half-gap). `ActionDrawer` centers the buttons horizontally and centers
the buttons plus an optional caption message (at most two lines, under the
buttons) vertically. Wide drawers keep the message on the left and the buttons
on the right. Every confirmation pair reads secondary then primary:
Revert/Keep, Cancel/Apply.

In Bar portrait, Keybindings rows keep the label on the left (wrapping to two
lines) and right-align the combo. A long combo may wrap onto a second
right-aligned line. Resolve is hidden there because the conflict card's Pick
another key does the same thing; the combo turns `Color.urgent` instead. The
conflict card's buttons stack centered.
