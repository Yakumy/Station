<!-- summary: Why an open panel closed or jumped to another output when the bar or a stock widget changed. -->
<!-- code: lib/panel/PanelSession* lib/panel/PanelIntent* lib/bars/Bar* -->
# Panel across bar rebuilds

Dated sections are investigations, oldest first. A later one can supersede an earlier one.

## Bar changes under an open panel

| Fact | Tag |
|---|---|
| Omarchy's stock-adapted bar swaps `root.vertical`-keyed `Loader` components for the section container, center arrangement, and every module Row/Column (stock `Bar.qml` 1287/1557/1746). An axis flip therefore destroyed the Station widget and its popout; the visible asymmetry followed from the open panel being hosted on eDP-1. Station replaces those swaps with orientation-agnostic hosting and `BarModel.positionModules`, preserving the module instances through an ordinary flip. | [SRC] |
| That inner repair was necessary but not sufficient. Live repetitions after `128bee0` found intermittent bursts where a `shell.json` position write caused both `omarchy-bar` surfaces to close and reopen; `hyprctl layers -j` showed new surface addresses, while the Quickshell log created duplicate widget IPC handlers and then evaluated callbacks against invalid `MonitorBar` contexts. Other repetitions were clean, so a simulator or single successful flip does not establish host-window continuity. Station now treats validated `config.bars` as the live authority while its panel is open: top-level `Bar.qml` reads the detached service snapshot and moves locally, and the service writes the redundant `shell.json` `bar.monitors` mirror only after the panel closes. Structural rebuilds and display-origin remaps still use the evacuation hand-off. | [LIVE][SRC] |
| After that host-write deferral, same-axis moves were clean and moving the other monitor's bar left the eDP-1 panel stable, but changing the panel-owning eDP-1 bar horizontal↔vertical still produced a shorter glitch. Retaining the panel's Quickshell screen did not remove it. The remaining mismatch is geometry: `bar.position` changes before the owning layer window swaps between full-height/thin and full-width/thin, so `Ui.KeyboardPanel.cardOrigin` briefly evaluates the new edge using old-axis `barW`/`barH` (for example, `top` with the old full-height left-bar `barH`). Station now holds the panel's last geometrically valid edge until the anchor window dimensions match the requested axis. This mechanism is source-derived and awaits the repeated physical flip check. | [LIVE][SRC][INFER] |

## Reopening and remembered selection

| Fact | Tag |
|---|---|
| `shell.summon` chooses an already open bar widget first, otherwise the focused output. Restoring a destroyed popup through it can move Station to the primary/focused monitor. A `monitoradded` event handler also called `openPanel()` unconditionally, even when the user had closed the panel. The replacement widget now restores on the saved output, falls back if that output disappeared, and the event handler no longer summons a panel. | [SRC] |
| Disabling/enabling `omarchy.workspaces` changes the bar layout and recreates Station widgets. During that hand-off a transient close can clear both the reopen intent and remembered tab. Station now keeps the intent for a short transfer interval around the setting change and display preview; an explicit user close clears that interval. Repeated preview drags continue in the same 12-second confirmation session and retain the original Revert baseline. This repair is source- and isolated-test-verified; a physical monitor move under the new code remains to be checked. | [SRC][QTTEST] |
| Disabling/enabling `omarchy.monitor` likewise rebuilds the bar. The Display-icon setting uses the same panel-transfer interval, but a distinct persisted lease containing the widget's original section/index and whether Station actually disabled it. Cleanup receives both validated leases and restores both only after confirming Station is no longer enabled. | [SRC] |
| A rebuilt Station panel previously initialized `selectedDisplayName` from the first draft display (`eDP-1` here). Selecting `HDMI-A-2` in a panel on that output then moving it rebuilt the panel and selected `eDP-1`; moving it from a panel on `eDP-1` concealed the reset because the fallback matched the selection. The selected connector now lives on the service and the inspector uses it again after a rebuild, falling back only while that connector is absent from the draft. | [LIVE][SRC] |

## Panel closing for another monitor (2026-11-05)

- [SRC] `stagePreviewApply` and `revertPreview` requested evacuation for any topology change
  while the panel was wanted, so a panel on HDMI closed and reopened when eDP-1 was turned off.
- [LIVE] With the panel open on HDMI-A-2, `hyprctl layers` lists `omarchy-keyboard-panel` on
  HDMI-A-2 and `omarchy-keyboard-panel-dismiss` on eDP-1. `KeyboardPanel` gives the twin
  `WlrKeyboardFocus.None`, and it uses no `HyprlandFocusGrab`.
- [LIVE] In a scratch Quickshell instance, a `Variants` declared inside a `PanelWindow` appears
  in its `data`, its `instances` are the windows with their `screen`, and assigning
  `visible = false` sticks.
- [SRC] Node transaction tests cover the order of release before the monitor rule.
  The real output removal with a kept panel has not been run: it is a topology change.
