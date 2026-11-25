<!-- summary: Investigations of rotation and scale geometry, edge snapping, the internal-monitor Off flag, Omarchy's own display panel. -->
<!-- code: lib/displays/** lib/platform/Transactions.js -->
# Rotation, scale, snapping and the Off flag

Dated sections are investigations, oldest first. A later one can supersede an earlier one.

## Rotation changed size without changing position (2026-10-24)

- **[SRC]** A rotation handle changed only `transform`. Since transforms 1/3/5/7
  swap logical width and height, the resized rectangle kept its old top-left
  coordinate and could grow into an attached neighbor; shrinking along their
  shared axis could instead leave a gap.
- **[SRC][QTTEST]** Rotation now preserves the strongest pre-change shared edge,
  resolves any remaining collision toward a side that was non-overlapping in
  the valid old layout, and publishes transform plus corrected position in one
  service update. Production QML coverage includes both horizontal neighbors
  and the reported 1920×1200-above-1920×1080 arrangement. This is isolated
  geometry and pointer verification; physical compositor acceptance remains a
  user check.

## Scale changes disconnected attached outputs (2026-10-24)

- **[SRC]** The direct Scale control changed only `scale`. Increasing scale
  shrinks the output's logical rectangle; when the edited output was left of or
  above a neighbor, its far edge moved inward while its top-left coordinate
  stayed fixed, leaving a logical gap that the pointer could not cross.
- **[SRC][QTTEST]** Direct scale and resolution transactions now run the same
  bounded resize placement used by rotation before generating the saved monitor
  block. The new value and corrected integer position publish together. Tests
  cover either member of a horizontal pair, assert edge contact and no overlap,
  and still verify one watched apply without a preview or forced reload. Physical
  compositor acceptance remains a user check.

## Edge snapping forced unequal monitors to corners (2026-10-24)

- **[SRC]** Drag snapping used the same theme-scaled screen-distance threshold
  for both edge attachment and parallel-edge alignment. At the default fitted
  zoom, a desired 60-logical-unit centered offset could lie within that broad
  threshold of both top and bottom alignment, so the cross axis snapped to a
  corner even while the intended side edge was correct.
- **[SRC][QTTEST]** Attachment and alignment candidates are now separate. The
  attachment axis retains the easy screen-distance snap; the parallel axis
  aligns only within 20 logical units and otherwise remains on its 10-unit grid
  position. Pure and production-pointer tests cover a 1920×1200 monitor centered
  at a 60-unit offset beside a 1920×1080 monitor, plus exact top and bottom
  alignment. Physical drag acceptance remains a user check.

## Internal-monitor Off toggle handoff (2026-11-04)

- [SRC] `omarchy-hyprland-monitor-internal off` writes the generated
  `~/.local/state/omarchy/toggles/hypr/internal-monitor-disable.lua` flag.
  Omarchy loads toggles after user monitor rules, so saving an enabled monitor
  rule alone cannot persist On while this flag remains.
- [LIVE] On the two-monitor eDP-1 / HDMI-A-2 setup, Station's explicit On → Keep
  successfully cleared the recognized flag in two successive cycles. The output
  remained enabled across reload; no personal-override error or config error
  appeared. Running the exact Off command again was observed without replay.
  On → Revert retained the flag. The test used the card handler through IPC,
  not physical pointer input. Initial internal-Off/external-On state and exact
  `monitors.lua` bytes were retained afterward.
- [SRC] Ordinary Keep still uses watched apply. This two-file exception pauses
  automatic reloads, saves both changes, explicitly reloads once, and restores
  the previous autoreload option. Rejected applies conditionally restore both
  files; modified toggle Lua is not removed. See the [Off flag contract](../contracts/displays.md#internal-monitor-off-flag).

## Internal Off flag and re-enabled outputs (2026-11-05)

- [SRC] `omarchy-hyprland-monitor-watch` runs `omarchy-hyprland-monitor-clamshell` on
  every monitor event, then 1, 3 and 7 seconds later, and every 2 seconds on a laptop
  with an active external output. Clamshell calls `monitor-internal recover`, which
  deletes the Off flag and runs `hyprctl reload` when no external output is active.
- [LIVE] With the flag present and Single `HDMI-A-2` saved, a preview of Single `eDP-1`
  showed `eDP-1` on and `HDMI-A-2` removed for about a second. The flag then vanished,
  the saved layout came back and the preview ended with `Display connection changed`.
  The same preview without the flag worked.
- [LIVE] Moving the flag out of the toggle directory fires `configreloaded` when
  autoreload is on. Moving it back fires nothing.
- [LIVE] `hyprctl eval` of a full `hl.monitor` rule answers `ok` in about 8 ms, before the
  output exists. Six raw enable-then-focus runs on `eDP-1`: three answered `monitor not
  found` first and all three succeeded on the next attempt, within 0.8 seconds. This is
  what `Could not focus the surviving display` reported.
- [LIVE] After a saved Single, Extend previewed with no change: the draft reads the other
  output as disabled, and `setModeValue` did not enable it. This needs no flag. Existing
  tests missed it because they left Single inside one preview session, where the draft
  still had both outputs enabled.

## Monitor turning off during a bar toggle (2026-11-05)

- [LIVE] `monitors.lua` was saved at 17:43:19 with Single on HDMI-A-2 and eDP-1 disabled, and it
  was the only `monitors.lua` write in that window. A bar surface was created at 17:43:58, the
  panel changed at 17:44:15, and the map was committed to HDMI-A-2 alone at 17:44:18. Status
  reported `Preview timed out.`, saved mode `single`, and eDP-1 disabled.
- [INFERRED] eDP-1 was on only as an unsaved preview. The 12-second countdown ran out while the
  Bar tab was showing, and Revert restored the saved Single. The bar toggle did not cause it:
  `setMonitorBarEnabled` issues no monitor rule. This was reconstructed from timestamps.
- [SRC] The countdown was drawn only by `DisplaysTab`, so nothing warned on other tabs.

## Omarchy's display panel choices win over monitors.lua (2026-11-22)

- **[SRC]** Omarchy's `default/hypr/monitor-settings.lua` reads
  `$XDG_STATE_HOME/omarchy/monitors/settings`, one line per physical monitor (mode,
  position, scale, transform, identity), and applies it with `hl.monitor` after
  `hypr/monitors.lua` on every config load and on `monitor.added`. A choice saved there
  wins over Station's marked block. `omarchy-hyprland-monitor-persist OUTPUT SCALE
  [MODE] [POSITION] [TRANSFORM]` is the only writer. It accepts a mode without the `Hz`
  suffix, never moves a monitor, and updates `GDK_SCALE`.
- **[LIVE]** Omarchy's file held `scale 1` and a position for each monitor. After a
  Scale change, Station's block held `scale = 1.25` for eDP-1, the output ran at 1, and
  Station showed "Personal Hyprland rules override part of this layout". Keep now saves
  Station's values there first.
- **[INFER]** The tests missed it because every display harness doubles Hyprland and
  models only Station's own block. None loads Omarchy's config, so none could see a
  rule applied after it.
