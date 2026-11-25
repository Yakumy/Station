<!-- summary: KeyboardPanel structure and sizing, pointer input on the layout canvas, host dropdown and slider behavior, brightness and text size commands. -->
<!-- code: lib/panel/** Panel.qml -->
# Panel popout, canvas and controls

Dated sections are investigations, oldest first. A later one can supersede an earlier one.

## Popout structure

| Fact | Tag |
|---|---|
| The on-demand `panel` loader does **not** inject the `anchorItem` and `bar` that `KeyboardPanel` requires, so use the **Display popout structure**: a bar widget whose entry `Panel.qml` is a `qs.Ui` popout. | [SRC] |
| Display's building blocks: `qs.Ui.Panel`, `BarIconButton`, `KeyboardPanel`, `PanelKeyCatcher`, `ScrollView`, `PanelSectionHeader`, `PanelSeparator`, themed controls. Source: `/usr/share/omarchy/shell/plugins/panels/monitor/` (`Panel.qml`, `Model.js`, manifest id `omarchy.monitor`). | [SRC] |
| The popout rendered anchored at `(5,27)` under the widget on `eDP-1`, took keyboard focus, closed on Esc and on outside click. **A requested `Style.space(680) × Style.space(560)` rendered as 567×467 logical pixels** under the active theme and scale: design to the available size. | [LIVE] |
| `Ui.KeyboardPanel.centerOnBar` centers only along the bar: with a top or bottom bar its vertical coordinate stays next to the bar. Its `gap` determines the perpendicular coordinate, and the card is clamped within the screen margins. Station's Center preference computes that gap from the desired card size and selected screen, keeping the host's focus, dismissal, and bar hand-off behavior. | [SRC] |
| Offscreen Qt backend cannot load `KeyboardPanel`; component checks need the Wayland session. | [LIVE] |

## Layout canvas and pointer input

| Fact | Tag |
|---|---|
| Replacing a JavaScript-array `Repeater.model` immediately destroys its delegates. The original drag release wrote X with `setDisplayValue`, then failed with `ReferenceError: root is not defined` before writing Y or calling Preview. Commit X/Y in one update and continue the transaction from a component outside the Repeater. Reproduced with the production handler in Qt's offscreen pointer harness. | [QTTEST] |
| Qt's `MouseArea.drag.target` starts moving after its drag threshold; an exact pointer displacement can therefore leave a card short of the desired edge. The repaired layout derives offsets from press/release coordinates in the canvas, keeps its transform stable during the gesture, and snaps within a theme-scaled 12-screen-pixel distance. Its fit reserves room for horizontal and vertical arrangements. | [QTTEST][SRC] |
| A `MouseArea` inside the panel's vertical `ScrollView` loses its pointer grab to the underlying `Flickable` once a drag is recognized. Quickshell then calls `onCanceled`, so the card visually moves and snaps back without the service entering Preview. Set `preventStealing: true` on draggable monitor cards. The regression harness must embed the production layout in a scrolling `Flickable`; testing the component as a bare `Item` misses this behavior. | [QTTEST][LIVE] |
| Isolated layout tests cover horizontal placement on either side, vertical placement, negative positions, repeat drags after Revert, click without Preview, edge snapping, selected-mode/scale/rotation geometry, and three large displays fitting the canvas. Scaled/rotated and three-display **hardware** behavior remain unverified. | [QTTEST] |
| A position-only preview used to evaluate the full managed monitor block, including a rule for every unchanged output. That can reconfigure the other monitor as well as the dragged one. The runtime preview now emits a rule only for each output whose position changed when mode, enablement, scale, rotation, and resolution are unchanged. Keep still writes the complete guarded block. Rotation/topology edits still use the guarded preview; Scale/Resolution/Refresh now bypass preview and persist directly. | [SRC] |
| The enlarged layout canvas supports a user zoom factor around the pointer and independent pan offsets. Isolated Qt pointer tests verify zoom preserves the targeted card point, background panning does not change display coordinates, and dragging a monitor still commits one preview. These are UI-transform tests only; no live compositor reconfiguration was exercised. | [QTTEST] |
| Rotation controls drawn outside a monitor-card child can paint there but are not reliably clickable beyond that child's bounds. Put the selected monitor's borderless controls in a canvas-level overlay above all cards instead. Each icon sits diagonally outside a corner, with a broad hover target extending both outside and inside the card; cap its inside reach at half the card size so adjacent corner targets do not overlap on narrow cards. Isolated pointer tests exercise hover on each corner and clicks with side-by-side cards and an icon overlapping a taller neighbor. | [QTTEST] |

## Host controls

| Fact | Tag |
|---|---|
| `Ui.Dropdown.selectCurrent()` imperatively assigns `root.value` before emitting `changed`. A normal `value: selectedMonitorSetting` declaration therefore loses its binding after the first Background choice, leaving the trigger on the last chosen label across monitor selection and panel reopen. An explicit QML `Binding` object remains authoritative and reasserts the selected monitor's persisted mode whenever either the service snapshot or selection changes. | [LIVE][SRC] |
| The host `Ui.Dropdown` sizes its trigger and popup to the caller's `width`, with its chevron anchored at the trigger's right edge. Equal-width toolbar dropdowns therefore put excessive space between a short value and the arrow. The 2.0 render instead places compact Mode and Direction text menus in the top tab row; Station uses content-sized triggers and keeps Mode's popup wide enough for named Single-output choices, right-aligned so it stays inside the panel. | [SRC] |
| The stock Display panel's text-size control uses seven stops (`9, 10, 11, 12, 14, 16, 20` px) and runs `omarchy-display-text-size <px>`. That CLI changes the shell base font and GTK scaling; `Style.font.baseSize` follows via a file watch. Station reuses those stops and command, with a pending value while the style change is in flight. | [SRC] |
| `Ui.PanelSlider` supports integer-valued index sliders with visible `tickCount`, and emits `released` for both pointer release and mouse-wheel steps. Resolution and refresh bars can therefore index the display's exact allowlisted modes instead of interpolating unsupported values. Scale/Resolution/Refresh persist the final discrete choice with one atomic watched-file transaction and do not create a preview/countdown session. | [SRC] |
| The stock Display panel runs `omarchy-hyprland-monitor-scaling`: first a runtime `hl.monitor` for the focused output, then (when Omarchy's generic variables are present) `sed` on `monitors.lua`. On the affected system the 2026-10-08 audit records a requested `1.6` for `eDP-1`, while later explicit `eDP-1` and Station managed rules still declared scale `1`; the watched reload therefore reapplied `1` because the last rule wins. This explains the transient resize, multiple output refreshes, and final old value. The stock global-scale editor is not an authority over a file containing later exact per-output rules. | [LIVE][SRC] |

## Brightness

| Fact | Tag |
|---|---|
| Public CLI: `omarchy brightness display [--no-osd] [--monitor name] [+N%\|N%-\|N%\|off\|on]`. Write example: `omarchy brightness display --no-osd --monitor <name> 40%`. | [LIVE] |
| Read: `omarchy-brightness-display --monitor <name>` prints the percent on line 1; empty or `unavailable` means unavailable. Display's panel parses it with `parseInt`, clamps 0–100. | [SRC] |
| The binary routes internal panels to `brightnessctl`, ordinary external monitors to DDC/CI, supported Apple displays to an Apple helper. | [SRC] |
| **Never call `omarchy-brightness-display --help`:** the direct binary has no help handler and treats it as an adjustment argument. Use `omarchy brightness display --help`. | [LIVE] |
| Display's `Model.js` does not read brightness; it only clamps, labels and computes scale and parses display JSON. Reading goes Panel.qml → `omarchy-monitor-state` (every 5 s while open) → `omarchy-brightness-display --monitor <focused>`. | [SRC] |

## Fixed panel frame and bounded overflow (2026-11-04)

- [SRC] StationPanel previously passed the visible tab Column's implicit height
  into KeyboardPanel fitting and centered placement. Shorter tabs therefore
  shrank the card. It now requests fixed theme-scaled width/height (996/620),
  retaining host screen limits. Centered placement uses the same fixed request.
- The earlier non-scrollable reference is revised: header/tabs remain fixed;
  a shared body viewport scrolls only on vertical overflow. Tab changes reset
  its position. Existing DisplayLayout pointer-stealing prevention is retained.
- Isolated Wayland check (`test/qml/panel-size.py`) verified constant card
  dimensions across all six tabs, synthetic expanded content, scroll reset and
  a shortened viewport. It runs without a Station service and qualifies bare
  Color references in its temporary copy to avoid theme-name ambiguity in the
  isolated context; production geometry and event handling are unchanged.
  This is a panel harness, not live monitor or keybinding acceptance.

Validation: 214 Node tests, 23 existing offscreen layout tests, the isolated
panel-size harness, theme-token scan, live-backend component compilation and
whitespace checks passed. The layout harness retains its known theme-double
warnings. Installed visual acceptance remains a user check.
