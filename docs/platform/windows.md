<!-- summary: Gaps, split, rounding and animation through hl.config, direct persistence, the Windows preview. -->
<!-- code: lib/windows/** -->
# Window settings

Dated sections are investigations, oldest first. A later one can supersede an earlier one.

## Windows controls (2026-11-01)

- [LIVE] Hyprland remains 0.56.2 (`efb5099`); bounded `hl.config` gaps,
  Dwindle split ratio, rounding, animation enable and `hl.animation` window
  leaves accepted the generated default Windows settings. `configerrors` was
  empty; a reload restored file-based settings afterward.
- [SRC] Omaland's installed service only manages its launcher; its saved block
  currently sets `dwindle.split_width_multiplier`. Disabling that plugin does
  not erase the block. Station does not write that option.
- [QTTEST] Current check-layout runner reports Qt 6.12.0 / Omarchy 4.0.6;
  its 23 existing pointer tests passed. They do not exercise the new Windows UI.
- Windows validation: 210 Node tests passed sequentially, theme-token scan,
  clean-export plugin validation, and live-backend component compilation passed.
  A parallel watchdog test failed its timing assertion; the sequential run passed.
  Actual slider interaction, geometry and animation feel await user acceptance.

## Windows acceptance corrections (2026-11-01)

- User testing found the split percentage affected the old window. Generation
  now uses `(100 - nextPercent) / 50`; 28% therefore emits 1.44.
- [LIVE] `hl.workspace_rule` accepted `workspace="m[eDP-1]"` with a
  directional `gaps_out` table; `configerrors` stayed empty. Reload restored
  saved settings. The service generates one monitor selector per connected
  output and reapplies on preference changes and runtime rebuilds.
  Syntax follows the installed Lua stubs and
  https://wiki.hypr.land/configuring/core/rules/workspace-rules/.
- The preview now swaps once after a changed speed is released, with no repeating
  timer. Its outer canvas uses BarLayout's dotted pattern, insets and border.
- 211 regression tests, 23 existing layout tests, theme scan and component
  compilation passed. Final new-window proportions and visual acceptance remain
  user checks; the directional-rule probe confirms API acceptance only.

## Full Windows layout and independent rounding (2026-11-04)

- [SRC] Installed `qs.Commons.Style.cornerRadius` mirrors Hyprland's global
  `decoration.rounding` (Style.qml). The Windows slider now uses application
  window rules rather than changing that global value. A cache bounded to the
  original 41 preview radii (later corrected to 21 supported radii below)
  reuses handles and disables the previous active rule.
- [LIVE] Generated rounding rule accepted without configuration errors; the
  global corner value stayed 7 before/after applying radius 12. Reload restored
  saved runtime configuration after the probe.
- WindowsLayout now shows the full displayDraft topology using BarLayout bounds,
  sizing and bar geometry. Bars use neutral text color and Pill uses three
  rounded segments. Each monitor has two windows; changing speed exchanges the
  WINDOW rectangles on the first two monitors, once. NEXT WINDOW stays put.
  Header alignment is corrected and the selected-monitor control caption removed.
- 213 Node tests, 23 existing layout checks, theme scan and component compilation
  passed. `test/qml/windows-tab.py` renders the production tab with host
  tokens and verifies both exchange destinations/movement. The rendered artifact
  was inspected; this is an isolated preview check, not a live window migration.

## Windows preview labels, rounding and transfer reflow (2026-11-04)

- [SRC] The old preview painted a full preview-pixel border around a radius
  scaled by monitor zoom. At small zoom that border obscured the requested
  rounding. The outline now paints at logical monitor size and scales border
  and radius together, with antialiasing and non-aligned border pixels. This
  changes only the illustration, not compositor rules or shell corner tokens.
- [SRC] Independent position Behaviors did not model tile occupancy or animate
  size. WindowPreview.js now keeps stable identities across two transfers:
  first monitor to second (one/three tiles), then the original second-monitor
  window back (two/two tiles). One timeline interpolates all four geometry
  properties; a released speed is captured and subsequent releases queue the
  latest replay. Only the first two enabled monitors participate.
- Isolated Wayland/host-token check: external upper-left names, a non-overlapping
  label lane on stacked monitors, initial/replay continuity, intermediate tile
  expansion/shrinking, queued speed, zero speed and radius scaling passed.
  The rendered 40 px rounding artifact was inspected. This verifies the preview;
  no real monitor topology or application windows were changed. Animation feel
  remains subject to user acceptance in the installed panel.
- Validation: 214 Node tests passed sequentially outside the sandbox. Two Lua
  subprocess test files timed out inside the sandbox. The existing offscreen
  layout harness passed 23 tests with its existing incomplete-theme-double
  warnings; theme-token scan, clean-tree plugin validation, live-backend QML
  compilation and diff whitespace checks passed.

## Window-rule rounding limit and tile order correction (2026-11-04)

- [LIVE, user report] Hyprland rejected the generated window rule at rounding 32
  with "value 32 is more than the maximum of 20". The previous radius-12 probe
  established acceptance only at 12; rendering a radius-40 preview did not
  establish compositor support. Station now bounds rounding to 0–20 in shared
  sanitization, slider limits and Lua generation. Previously saved higher values
  clamp to 20 on read. The rule cache therefore has 21 supported values.
- WINDOW now occupies the left tile and NEXT WINDOW the right tile, whose
  width follows the next-window split percentage. During arrival the right tile
  splits vertically, placing the incoming WINDOW above NEXT WINDOW; the left
  resident WINDOW remains in place. Departure expands the remaining tile.
- Validation: all 214 regression tests, the isolated host-token render/exchange
  check, theme-token scan and whitespace checks passed. The render check now
  uses the supported upper bound of 20 and asserts WINDOW precedes NEXT WINDOW.

## Window slider direct persistence (2026-11-04)

- [SRC] The first v3 window save reused `Transactions.settings`: replacing
  `looknfeel.lua` triggered a compositor-wide watched reload, and `sleep 1`
  occupied the service action queue before read-back. The prior local-knob fix
  did not remove that delay or reload.
- [SRC] Hyprland v0.56.2's `ConfigWatcher.cpp` removes watches when
  `misc:disable_autoreload` is true and reattaches them when restored. The
  dedicated window transaction suspends watches, compares sources again, saves,
  compiles the file and applies one generated setting, then restores autoreload.
  Only error recovery reloads; personal Lua wins again on the next normal reload.
- [LIVE] A reversible 37 → 38 → 37 split test took 69.8 / 69.3 ms per transaction,
  with no socket2 reload event and identical cursor coordinates before and after.
  Original file bytes, runtime split and autoreload were restored; config errors
  were empty. This tested the helper, not physical pointer input in the panel.
  Evidence: `/tmp/station-window-setting-results.json`.

## Windows preview on one and three monitors (2026-11-11)

- [SRC] The preview selected only the first two enabled outputs and returned
  immediately with one. It now rotates WINDOW identities through every enabled
  output. With one, WINDOW and NEXT WINDOW swap twice, returning to their original
  left/right slots. These are simulated tiles only.
- [QTTEST] The production clock completes one-, two- and three-output cycles,
  queues the latest speed, and survives equivalent monitor snapshots. The host
  Windows-tab harness checks all three cases, midpoint reflow and final sides.
- [SRC] Interpolation now returns exact endpoint rectangles to avoid floating-point
  drift at replay boundaries. The former Windows-tab `ordered exchange` assertion
  also uses a subpixel tolerance; the previously recorded failure no longer occurs.
