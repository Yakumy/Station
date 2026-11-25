<!-- summary: Workspace rules, moves, renumbering by Omarchy, reconnects, scratchpads, four outputs. -->
<!-- code: lib/stations/** -->
# Workspace behavior

Dated sections are investigations, oldest first. A later one can supersede an earlier one.

## Workspaces and rules

| Fact | Tag |
|---|---|
| A runtime `hl.workspace_rule({ workspace = "N", monitor = "NAME" })` places a **newly created** workspace on that monitor (tested with a fresh number, `500005`). | [LIVE] |
| The rule **does not move an existing workspace**. Apply rules before the first focus or move into a station. | [LIVE] |
| Runtime workspace rules vanish on `hyprctl reload`. | [LIVE] |
| Empty workspaces are destroyed by Hyprland; a spare workspace can be created and destroyed in the same millisecond during an unplug (see [Events](hyprland-config.md#events-hyprland-socket2-and-quickshell)). | [LIVE] |
| `hyprctl clients -j` gives each client `address`, `workspace.id`, `monitor` (numeric id), `pinned`. After a monitor is removed, client workspace ids are unchanged and only the monitor id changes (e.g. 1 → 0). | [LIVE] |
| Station's original fixed three-lane grid was superseded on 2026-10-05 by the accepted compact mapping: `workspace = (station − 1) × activeWidth + slot`. Single/Mirror width is one; Extend width is the managed active-output count. The durable mapping records output order. Special and named workspaces and pinned windows are excluded from migration. | [SRC] |
| Resolve a client's numeric `monitor` against the current `hyprctl monitors all -j` entries' **`id`**, then use the connector name. Monitor IDs are not Station lane numbers or array indexes. The key repair required this conversion for both client snapshots and `activewindow`. | [LIVE][SRC] |
| When compact numbering reuses an existing destination workspace, set its rule **and explicitly move that workspace to the intended monitor**. Window moves into an existing workspace alone inherit its previous physical placement. The local upgrade audit confirmed preservation of each window's physical display and station after adding this step. | [LIVE][SRC] |

## Directional move after display reconnect (2026-10-08)

- **[SRC]** A native directional move across monitors used the destination
  workspace selected by Hyprland to infer the window's station. A reconnected
  output can retain an unrelated active workspace; if that workspace was 12 in
  a two-output grid, Station decoded it as Station 6 and synchronized both
  displays there. This explains the observed S1, S2, S3, S6 result after moving
  an S1 window back to HDMI.
- **[SRC]** A physical monitor crossing now derives the station from the
  pre-move workspace. If Hyprland lands the window on a different station,
  Station first corrects it to the same station on the destination output and
  only then synchronizes display focus. Native tile rearrangement within one
  monitor is unchanged.
- **Verification:** `test/unit/window-actions.test.cjs` models a reconnected
  destination whose active workspace is 12. Moving an S1 window to it must end
  on workspace 2 (S1's second-display slot), retain Station 1, and never focus
  workspaces 11 or 12.

## Scratchpad retrieval rejected by Station (2026-10-16)

- **[LIVE][SRC]** On Hyprland 0.56.2, Omarchy's `SUPER+ALT+S` sends windows to
  `special:scratchpad` and `SUPER+S` toggles it. Station owns the numbered send
  bindings. The live `yakumy.station status` reported the user's last numbered
  send as `action: "send", station: 2, result: "unmanaged"`; `hyprctl clients`
  showed an unpinned foot window on workspace -98, `special:scratchpad`.
  `hyprctl configerrors` was empty. `readActiveWindow` reused `Grid.eligible`,
  rejecting special workspaces before dispatching a window move.
- **[SRC]** Numbered sends now opt into a narrow exception for the active,
  unpinned `special:scratchpad` window on a managed output. Directional actions
  and topology migrations keep their existing exclusions.
- **Verification:** `test/unit/window-actions.test.cjs` exercises retrieval on
  either display and on a single display, follow and silent sends, and rejection
  of pinned, unmanaged, named and other special windows. These isolated tests
  do not prove a physical keypress or the installed compositor path.

## Double move and station 6 (2026-11-05)

- [LIVE] `hl.unbind` matches the registered modifier order. On a free key,
  `SHIFT + CTRL + SUPER + F23` did not remove a bind registered as
  `SUPER + SHIFT + CTRL + F23`, and the same spelling did. `CTRL + SUPER + LEFT` showed the
  same trap earlier, but the 4.5.0 move binds were then added in the wrong order.
- [LIVE] `hyprctl binds` listed both `Move window to right monitor` and
  `Station: Move window right` on one key. Omarchy's moved the window to eDP-1, then
  Station read it there and stepped past the outer edge to the next station.
  `lastWindowAction` recorded a `right` move starting on eDP-1. The IPC call alone, with
  disposable terminals, kept the station from HDMI-A-2 to eDP-1 on empty and occupied
  destinations, which is why earlier IPC runs never showed this.
- [SRC] Omarchy's `monitor-workspaces.lua` reconciles on `config.reloaded`,
  `monitor.added` and `monitor.removed`. With eDP-1 in block 0 and HDMI in block 1, an odd
  Station workspace on HDMI belongs to eDP-1 by number, so `adopt` renumbers it: 1 to 11,
  3 to 13, 5 to 15. In a two-output grid, 11 is station 6. Station cannot tell a renumbered
  workspace from a real one, so it adopts the result.
- [SRC] `test/unit/workspace-authority.test.cjs` runs that module under a fake compositor
  and records 1 to 11 and 5 to 15. [INFERRED] A Throne window on workspace 15 on HDMI-A-2,
  found after the 15:51 theme change, is that same renumbering of station 3.
- [SRC] `SUPER + SHIFT + ALT + arrow` was documented as unbound but never was. It runs
  `move_to_monitor`, which renumbers the same way.
- [LIVE] Evaluated Lua shares the configuration's state: `o.workspaces` is the module table
  that `hl.on` handlers call through, so replacing `reconcile` takes effect at once.

## Omarchy's workspace indicator with Station's numbering (2026-11-10)

- [SRC] Omarchy 4.5 gives each monitor a block of ten workspace IDs, keyed by make, model
  and serial, and records it in `~/.local/state/omarchy/monitor-workspaces` as
  `block<TAB>connector<TAB>identity`. The internal panel takes block 0 (1–10), the next
  monitor block 1 (11–20). An unplugged monitor keeps its line with an empty connector.
  `SUPER + n` runs `o.workspaces.focus(n, monitor)`, which shows block·10 + n.
- [SRC] Omarchy's indicator (`shell/plugins/bar/widgets/Workspaces.qml`) reads that file and
  knows nothing of Station. Each bar lists the first five IDs of its monitor's own block,
  and any other existing ID in the block, labelled `(id − 1) % 10 + 1`. After a gap it lists
  "visiting" workspaces: any other ID that sits on this monitor. The shown workspace is drawn
  as its layout glyph, not a number. A click on its own block calls `o.workspaces.focus`;
  a click on a visitor focuses that ID directly.
- [LIVE] Sync on eDP-1 (block 0) and HDMI-A-2 (block 1), station 1, with HDMI first in role order: HDMI
  shows 1 and eDP-1 shows 2. HDMI-A-2's indicator read `1 2 3 4 5`, a gap, the tiling glyph,
  `3`. The first five were empty workspaces 11–15. The glyph was workspace 1, which was shown, and
  `3` was workspace 3, station 2's HDMI side. Both were visitors, because 1–10 is eDP-1's
  block. eDP-1's indicator looked right only because Station's 2, 4 and 6 fall in its block.
- [INFERRED] The indicator matches Station only in Repetitive, which uses Omarchy's blocks.
  In Sync and Non-repetitive its numbered buttons lead to IDs outside Station's map, such
  as 11–15 above.
- [SRC] Omarchy 4.5's blocks (`default/hypr/monitor-workspaces.lua`) write no workspace rules;
  they renumber and move workspaces from the reconcile. A workspace rule with a number and
  a monitor therefore comes from the user's own configuration, or from Station once it has
  run, which is why Station reads `hyprctl workspacerules -j` only on a fresh install.
- [SRC] The indicator dims a workspace that is neither occupied nor shown to opacity 0.5,
  and draws the shown one as a `WidgetButton` icon glyph (U+F14FB while tiling) at
  `Style.bar.iconSize`.

## Four outputs (2026-11-21)

- **[UNIT]** GitHub issue #14. `four-outputs.test.cjs` runs the reporter's four
  monitors through lane assignment, all three workspace modes, the window plan and the
  monitor block. The `layout` harness renders their geometry, two outputs rotated
  around an ultrawide, and checks that the role menu offers 1 to 4.
- **[LIVE]** A Hyprland headless output stands in for a fourth monitor:
  `hyprctl output create headless STATIONTEST`, then `hyprctl output remove STATIONTEST`.
  On the maintainer's three-monitor desktop in Sync mode, it got lane 4, its bar and
  workspace rules 4, 8 … 40, and `configerrors` stayed empty. The six windows kept
  their output and station: workspace 8 moved to 10 and 6 to 7. `switchStation 2`
  showed 5 to 8 on all four outputs. Removal returned every window to its original
  workspace and left `monitors.lua` unchanged.
- **[LIVE]** Removal leaves two things behind. Runtime workspace rules 31 to 40 stay
  until a reload, because Hyprland cannot delete one runtime rule. Any shrink does the
  same, for example 21 to 30 when three outputs become two. The lane preference
  `display@STATIONTEST` also stays in `config.json`, as for any absent monitor. After a
  test, run `hyprctl reload`, remove that key and restart the shell.
