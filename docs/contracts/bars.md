<!-- summary: Per-monitor bars: sections, dragging, click targets, plugin widgets, presence, position, size, style, background and blur. -->
<!-- code: lib/bars/** Bar.qml -->
# Bars

Station's bar behaves as Omarchy's does, apart from a listed set of differences
([Omarchy's bar](../omarchy-bar.md)). `Bar.qml` hosts one Omarchy-derived bar per connected output. Activating it removes
Station's persisted widget row atomically and injects a virtual Station slot. Plugin
disable therefore removes the last enable reference and unloads the service. Never edit
packaged Omarchy files for per-monitor behavior.

Station preserves the host's six layout sections: `left`, `centerBegin`, `center`,
`centerEnd`, `right`, and `tray`. The flanking center sections grow away from the
center box without moving its anchor, horizontally or vertically. Their extents
count toward Pill backgrounds, minimum width, and maximum content size. Widgets in `tray`
render inside a tray widget that provides a `sectionHost`. Station needs Omarchy 4.5 or
later.

## Dragging

Dragging follows Omarchy's bar. A widget dragged past a small threshold lifts out, however
long it was held first, and room opens where it would land. Over the center box or the
tray's drawer it lands among the widgets there, or in them when empty; at the box's edges
it lands in the flanking section. A tray does not go into its own drawer. Pulled
well off the bar and let go, a widget is removed, except Station's own two, which go back.
Every widget keeps its instance through a drag and a side change. While a drag runs, the
whole surface takes input, so the pointer is never handed to a window below.

## Station's own widgets

Station's logo and indicator are two widgets on Station's bar, and one on Omarchy's. They
have no layout row while Station is the bar. Their places are `bar.stationWidget` and
`bar.stationIndicator`, the indicator follows the logo until it is moved, and an old
`bar.centerAnchor` still keeps its widget in the middle
([rules](../omarchy-bar.md#stations-own-widgets)).

## Clicks and hover

One full-bar IPC handler refreshes the hidden-state probe on every monitor.
The full bar answers Omarchy's `panelWidgetIdAt(section, index)` from the focused
monitor's bar, so Omarchy's Bar panel hotkeys (SUPER + CTRL + 1 to 9) open the Nth
visible panel in that section.

A click on a widget's slot goes to the topmost registered click target under the
pointer, by the same hit test as Omarchy's bar: the target's own shape, every
ancestor visible, opaque and enabled, and every clipping ancestor containing the
point. The slot's overlay takes the left button only and has no wheel handler, so
the wheel reaches the widget directly. Station never forwards it.

A widget slot clips only while it is dragged or being removed, as on Omarchy's bar. Its
Indicators widget hovers from past its own edges, and a clipping slot would never deliver
that hover.

## Plugin widgets

A third-party widget gets its `bar.shell` from Omarchy's `pluginShellForBarEntry()`.
That facade has no service lookup, so `bar.shell.serviceFor()` returns null under
Station's bar, even for the widget's own id. Omarchy builds it that way for every
replacement bar, and only Omarchy's own bar can request a facade with a service.
A widget that needs its service, such as a clone of `omarchy.audio`, shows but
cannot act. Station cannot reach another plugin's service and does not start a
second copy of one. The lookup has to be fixed in Omarchy. Until then, a plugin can
reach its own service through [its own bridge](../widget-services.md).

## Controls

| Control | Rule |
| --- | --- |
| Presence | At least one enabled output keeps a bar. A disabled output's remembered bar does not count. |
| Position | Four side arrows per monitor. Omarchy's Bar → Position menu and bar dragging change only their own monitor. Other monitors keep their edges. For 1.5 s after Station writes a bar setting or the menu's position, a value it has just replaced is its own echo and is not adopted ([why](../platform/bar-layout.md#bar-positions-that-went-back-2026-11-24)). A new value is adopted at once. When the writes settle, Station's last one stands. |
| Content size | From `Style.font.body` to the live maximum. Above the default, each module zooms uniformly. |
| Height | From the theme's thickness to 5% of the mode's shorter native side. A live minimum can clamp it. |
| Width | 1 to 100%. Requests below the measured non-overlap minimum stay visible and the bar clamps. |
| Enabled | The switch moves at once, and `BarLayout` applies the change after the throw, because building a bar blocks the shell's thread. While the panel is open the host write is deferred like every other bar control, because it would rebuild all widgets and the panel with them. Closing the panel in that gap still applies it. A refused change moves the switch back. Refusing the last enabled bar also shows a red message: "At least one bar must stay on. Turn on another bar first." A successful on/off edit clears it. |
| Background | Solid, Transparent or Blur. See [below](#bar-background-blur). A monitor with no saved row shows the host bar's `bar.background`: `none` (or the older `transparent: true`) is Transparent, `glassy` is Blur, and `opaque` or no value is Solid. Installing Station must not change how the bar looks, except for the [space Solid and Blur keep from the monitor](#bar-background-blur). |
| Style | Omarchy default, or Pill with separate left, center and right islands. |

## Bar background blur

A layer rule draws nothing while `decoration:blur:enabled` is false, which is Omarchy's
default. While at least one enabled bar is set to Blur:

- Station enables its `station-bar-blur` layer rule.
- If global blur is off, Station turns it on at runtime with 3 passes, records the passes
  it found, and enables a `no_blur` window rule, so windows look as they did.
- If global blur is already on, Station changes nothing else. Those settings are the user's.

When no bar wants Blur, Station disables the layer rule and returns what it changed. A
reload clears the override, and the next sync applies it again. Nothing is written to a
file or to `state.json`.

## Geometry, dragging and zoom

- A bar with a visible surface (Pill in every background, and Omarchy default in Solid or
  Blur) keeps a safe space of `Style.space(8)` from the monitor edge and from the ends of
  its span, at any width. A Transparent default bar begins at the physical edge. The bar
  reserves the configured thickness plus that space. Window gaps never move the bar.
- A side change reflows in place, so an open panel survives. While the panel is open,
  `config.bars` is authoritative and the shell config write waits for close.
- The panel follows the current bar edge and configured thickness. The host positions
  it using logical thickness, independent of transient layer-window dimensions.
- Drag empty bar space to move the bar. A widget drags itself, not the bar.
- Double-click empty bar space to step that monitor's background: transparent, blur, solid.
- The surface spans its screen, as Omarchy's does. Only the drawn bar takes input, and only
  the strip is reserved. Nothing takes input under a fullscreen window that covers the
  screen, unless a special workspace is open over it. Partial-length bars sit centered in
  the surface.
- `Bar.qml` answers everything Omarchy's shell asks of its bar, including `screenBarSizes`
  and `cycleBackground`, for the focused monitor or all of them.
- A monitor's `moduleWidgets` answers with a widget's copies on every monitor, as
  Omarchy's one bar does, because only one copy answers an IPC call and relays it.
- Content zoom scales the subtree, re-rasterizes text and decodes images at the matched
  physical size.
