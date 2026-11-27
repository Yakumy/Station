<!-- summary: Reserved space, spacing, edges, host sections, widget dragging, positions reverting, on/off stutter. -->
<!-- code: lib/bars/** -->
# Bar geometry, dragging and position

Dated sections are investigations, oldest first. A later one can supersede an earlier one.

## Monitor-scoped menu and drag positioning (2026-10-25 revision)

- The user clarified that bar movement must be independent on each monitor.
  This supersedes the all-bars-together behavior described above.
- [SRC] A drag now sends the originating bar's connector through the existing
  `setMonitorBarPosition` bridge action. It never uses whichever display happens
  to have keyboard focus when the gesture ends. The Omarchy menu's global edge
  change is translated into an edit of Hyprland's focused monitor only.
  Previously the global action loop assigned that edge to every saved monitor;
  that was the cause of the second monitor moving too.
- [SRC] Unconfigured peers are pinned to their previously inherited edge before
  the new global fallback can move them. Pending shell.json mirrors preserve
  those independent positions when an open panel closes.
- [QTTEST] Tests cover each menu edge, switching the target monitor, inherited
  peer positions, disabled saved outputs, appearance preservation, and drag
  origin routing for HDMI-A-1 and eDP-1.

- [SRC] The stock menu's current position is mirrored from the focused bar
  when focus changes, without moving a bar. This also makes choosing the same
  menu edge on two different monitors observable. Mirrors are deferred while
  Station's panel is open and never override a pending external menu request.

## Animation range and inset bar reservation (2026-11-01)

- Animation speed now has nine indexed stops from 0 to 2×. Index 4 is 1×;
  the requested upper-quarter stop is 1.24×. Fractional values survive service
  sanitization. A slow preview retains its animation for the full duration.
- [SRC] Inset bars previously reserved `barSize` while painting through
  `panelThickness = barSize + edgeCenterOffset`. With zero outer gap on the
  bar side, the inward extension overlapped tiled windows. Bars now use Auto
  exclusion for the entire surface in all background/style modes. The explicit
  `exclusiveZone` setter is removed (it switches Quickshell into Normal mode).
  API reference: https://quickshell.org/docs/v0.3.0/types/Quickshell/PanelWindow/.
- 212 Node regression tests, 23 layout tests, theme scan and QML compilation
  passed. Final rendering requires user acceptance.

## Edge-aligned bar correction (2026-11-01)

- User acceptance found the retained floating inset left unwanted gaps against
  monitor edges. All backgrounds/styles now share zero cross-axis offset and
  reserve exactly `barSize` via Auto exclusion. Pill islands also remove their
  outer inset and parallel theme-gap margin; padding remains inside the islands.
  This revises the earlier floating geometry while retaining overlap protection.
- 212 Node tests, 23 existing layout tests, theme checks and QML compilation
  passed. Physical visual acceptance remains a user check.

## Solid and Blur default bar spacing (2026-11-04)

- [LIVE, user report] Solid color / Omarchy default bars visibly touched tiled
  windows because Station forced their bar-edge workspace gap to zero.
- [SRC] The shared Windows.gaps policy now retains the selected outer gap on
  the Solid color or Blur default bar edge. Transparent and Pill keep the previous
  zero-extra-gap policy; disabled bars retain all four gaps. WindowsLayout uses
  the same function as generated workspace rules. Existing config-change
  synchronization reapplies the policy when background/style is changed.
  This revises the earlier blanket bar-edge omission; bar reservations are
  unchanged. Physical acceptance of the added spacing remains a user check.
- Validation: 214 Node regression tests passed, including all four edges,
  background/style combinations, enabled/disabled bars and zero/max gaps.
  The isolated host-token preview check confirmed the solid/blur/transparent work
  areas follow the shared policy: Solid and Blur match, and their difference
  from Transparent equals the selected outer gap at preview zoom. Theme-token
  and whitespace checks passed.

## Newer Omarchy bar sections (2026-11-10)

- [SRC] The installed host normalizes `left`, `centerBegin`, `center`, `centerEnd`,
  `right` and `tray`. Station previously returned only the original three sections,
  discarding the flanking widgets. Its settings delta, lease lookup, activation and
  detached cleanup validation also assumed three sections.
- [QTTEST] `bar-sections` exercises the production center layout, Pill bounds and
  drawer loader with widget doubles. Both orientations, two content sizes, light
  and dark surface values, an empty center, delegate removal and empty-drawer drop
  space pass. This does not prove physical pointer routing or a live tray popup.
- [SRC] `ShellIpc` remains available on the installed host. Station registers its
  bar target once in the full-bar entry and forwards hidden-state refreshes to
  every monitor copy, rather than registering one handler per output.

## Bar on/off switch stutter (2026-11-05)

- [SRC] `setMonitorBarEnabled` ran inside the switch's click handler. It updates the live bar
  preferences, which create or destroy the bar's layer surface, then rewrites the shell
  configuration, which re-evaluates every bar. All of it shares the thread that advances the
  switch's 120 ms animation. Omarchy's `MonitorBar` measures a surface rebuild at about 150 ms.
- [INFERRED] That block outlasts the animation, so the knob jumped instead of sliding. The
  hitch itself was not timed.
- [SRC] The other bar controls defer the host write while the panel is open, and the enabled
  state did not. `MonitorBar` says reassigning `layoutConfig` "rebuilds every widget on every
  monitor", so each toggle also destroyed and reopened the panel and the switch itself. The
  enabled state now defers too: `Bar.qml` reads live preferences every 100 ms, so the bar still
  appears at once. The throw delay stays, because that surface still builds on the same thread.

## Bar grab and panel edge repair (2026-11-11)

- [SRC] The module pointer area owns widget presses. Propagating a composed hold
  to the background cannot transfer its grab; the module now handles held moves
  through release or cancellation. Short drags retain widget reordering.
- [SRC] Current `KeyboardPanel.cardOrigin` uses logical `barThickness`, not the
  layer window dimensions used by the old edge guard. Pill's inset could exceed
  that guard's thickness tolerance, stranding the panel on its previous edge.
  The facade now follows the edge and configured height directly; centered-panel
  gap math uses the same logical thickness as the host.
- [QTTEST] Pointer coverage checks clicks, short reorder drags, held moves outside
  all four sides and cancellation. Panel session coverage checks repeated edge
  changes, custom height and transient screen retention without binding-loop
  warning suppression. Physical dragging and final placement remain user checks.
- Validation: `test/run.py all` passed 26/27 groups, including QML compilation
  and plugin validation. The Windows-tab harness failed `ordered exchange` on
  both this worktree and an unchanged archive of `f2f4cf6`; it is a pre-existing
  failure on this host. Full-run log: `/tmp/station-bar-fix-final.log`.

## Dragging bar widgets (2026-11-24)

- **[SRC]** Station's bar was Omarchy 4.0.6's with changes. Omarchy reworked dragging in
  `b7e900ced` (2026-10-14), and made the bar's surface span its screen in `e2d618ac2`
  (2026-10-19): on an empty workspace Hyprland picks a pointer target again on a surface
  commit, and a pointer past the strip was taken off the bar mid-drag.
- **[QTTEST]** `bar-drag` on 4.4.1's bar: Station's icon never moved, because its slot has
  no layout row to look up. A widget dropped before it went to the section's end. Holding a
  widget for 200 ms moved the bar. The surface was 26 px deep. On the bar ported to
  `94a8c3c33`, all scenarios pass, with the Ui and Commons of that revision and of v4.5.0.
- **[SRC]** Migration `1791969355.sh` splits the center section at `bar.centerAnchor` only
  where `bar.id` is empty or `omarchy.bar`, so a Station config keeps the key.
- **[QTTEST]** The real shell at `94a8c3c33`, with a copy of a real `shell.json`, Reel and
  Station in a scratch home on two nested outputs, drew a blurred Pill bar and a
  transparent one. Blur stayed within the pills. Physical pointer dragging, hotplug and the
  live session were not exercised.
- **[LIVE]** On 4.5.0's first build, after several position changes, the bar on eDP-1 drew
  and reserved the left edge but took no pointer input at all.
- **[QTTEST]** Cause: its input region was `Region { item: barContent }`. A Quickshell
  `Region` follows its item's own x, y and size. A move between opposite edges changes none
  of them, only the parent strip's position, so the input stayed on the old edge. With the
  compositor's pointer, `bar-drag` fails on exactly the four opposite-edge moves of the
  default style, and Pill passes because its inset moves `barContent` itself. Omarchy's
  region follows the strip, a direct child of the surface. Station's now binds the sum.

## Bar positions that went back (2026-11-24)

- **[LIVE]** A bar released at one edge went to another, and `shell.json` and Station's
  `config.json` once disagreed about a monitor's edge.
- **[QTTEST]** Traced in the real shell at `94a8c3c33` on two nested outputs, moving the bars
  every 0.4 to 1 s. Omarchy's shell holds `shell.json` in memory, writes it and reloads it
  from a file watch. About 200 ms after a write its memory showed the file before that write.
  Station took the older position for a menu request, wrote it, and adopted the next reload,
  so the two traded `left` and `right` and settled on the wrong one. 4.4.1 ended the same run
  with the two files disagreeing.
- **[QTTEST]** With replaced values ignored for 1.5 s and corrected after, six runs at 0.15 to
  1 s ended on the last position asked for, with the files agreeing and no flip. Echoes were
  seen up to 0.7 s after a write. `bar-echo.test.cjs` replays the sequence. In `bar-drag` the
  gesture itself asks for the edge it is released at, from every edge to every other.
- **[INFER]** Choosing the edge a bar had less than 1.5 s before, from Omarchy's menu, looks
  the same as an echo and is not applied.

## The strip-sized surface (2026-11-28)

- **[SRC]** Omarchy `e33c5a8f` (2026-11-26) sized the bar's surface to its strip. A drag that
  strays off the strip keeps the pointer only because Omarchy's Hyprland carries
  `held-pointer-without-keyboard-focus.patch`; stock Hyprland drops it on an empty
  workspace. A resize settles: clear strip, resize, then a frame at the new size.
- **[SRC]** Omarchy `4a2de629` (2026-11-27) compiles a plugin's bar widget only while
  `shell.json`'s `bar.layout` holds it, and registers the rest with a null component.
  Station's logo has no saved row, so on that shell it would never draw.
- **[QTTEST]** `bar-drag`, with the merged bar, ended about one run in three with
  `y == 0 but anchor doesn't have top and bottom` (or the `x` twin), a fatal Wayland error
  that ends the shell, during the moves between every pair of edges. `WAYLAND_DEBUG` showed
  Quickshell sending `set_size(0, 35)` and then `set_anchor(13)` from the GUI thread, with
  the render thread's `wl_surface.commit` between them. The settle asks for a frame after
  every swap, so one is usually in flight when the surface moves. Omarchy's bar has the
  same race. A 0 length is sent for any axis anchored on both sides, whatever the implicit
  size, so no order of anchors and sizes avoids it.
- **[QTTEST]** Moving the surface only once 32 ms pass with no swap: eight clean runs in a row
  (40 scenarios each). Not tested on a live session or real hardware.
