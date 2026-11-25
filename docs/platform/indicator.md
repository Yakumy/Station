<!-- summary: Open-app feed, icon sources and focus styling, indicator latency and live workspace. -->
<!-- code: lib/stations/OpenApp* lib/bars/Station* -->
# Station indicator and app icons

Dated sections are investigations, oldest first. A later one can supersede an earlier one.

## Open app indicators (2026-10-29, Station 2.3)

- **[SRC]** The app feed uses its own read-only monitor/client/active-window
  requests and coalesces relevant Hyprland events. It never updates the
  transaction's client or monitor snapshots. Actual physical placement and
  active workspace membership determine the list during partial migrations.
- **[LIVE]** `test/qml/open-apps.py` observed two windows on eDP-1 and one
  on HDMI-A-2, with only the HDMI-A-2 window focused. No monitor/workspace
  commands were dispatched. The same harness instantiated horizontal and
  vertical bar controls offscreen and verified disabling clears the feed.
  This is a data/geometry check, not a live visual or topology acceptance test.
- **[QTTEST]** The existing pointer-layout harness passed 23 tests. All 208
  Node tests, theme-token checks, QML compilation, and plugin validation of a
  clean export passed. Model cases cover partial migrations, Single/Mirror,
  role swaps, pinned/special windows, and focus. They do not establish new
  hardware evidence for hotplug, preview restoration, or three-output setups.

## App focus styling (2.3.2)

- **[QTTEST]** The since-retired `check-open-app-colors` harness rendered the production effect
  blocks with black, white, colored, and transparent artwork. Focused pixels
  match the requested accent within rounding tolerance regardless of source
  luminance; transparency survives. Unfocused pixels are grayscale and white
  artwork composites at 50% over black. The offscreen RHI/OpenGL harness needs
  graphics access; the restricted sandbox aborted its render backend.
- **[SRC]** A white alpha-preserving intermediate effect precedes accent
  colorization. Both source layers remain explicit, allowing the bar's content
  zoom to retain the resolution fix from 2.3.1. The theme checker permits white
  normalization only in this app-icon component; elevation effects stay banned.

## Original focused icons (2.3.3)

- **[QTTEST]** The updated pixel harness verifies original black/white/red
  artwork when focused, grayscale at 50% opacity when inactive, and centered
  80% scaling on both axes. The integrated bar smoke check and QML compilation
  pass. Focused images bypass the effects; the accent/white-mask pipeline from
  2.3.2 was removed at the user's request after visual review.

## App raster bindings (2.3.4)

- **[SRC]** App image decode and explicit layer texture sizes now bind directly
  to monitor DPR and the host's effective content size. The generic host scan
  skips these managed images, so it cannot overwrite their bindings. This also
  covers focus updates that replace delegates without resizing the module.
- **[QTTEST]** The integrated smoke harness recreates equal-count delegates
  with flipped focus, changes host content size, and checks image decode and
  layer texture dimensions against the required physical raster size. It and
  QML compilation pass. Final visual sharpness still requires user review.

## Station indicator latency (2026-11-12)

- **[SRC]** The replacement-bar label followed the full panel snapshot. With the
  panel closed, Compact On read it every 1 s; Off and On hover read it every 150 ms.
  The service changes `currentStation` only after its compositor batch succeeds.
  The drawer's 600 ms reveal animation is separate from this number update.
- **[LIVE]** On the installed two-output Station setup, one IPC switch and return
  settled at the service in 167 ms and 247 ms from invocation (including IPC and
  status-read overhead). The original station 2 was restored. This measures service
  completion, not the rendered label or a physical key press. Local evidence is
  `/tmp/station-switch-latency/results.json`.
- **[QTTEST]** The production panel with a fake confirmed station reproduced an
  847 ms label delay on the previous code in closed Compact On. The scalar bridge
  path updated it in 4 ms in the comparison run, with no full-snapshot read. These
  are samples, not scheduling guarantees; its timer interval is 50 ms. The full
  snapshot cadence, direct-service path and switching protocol stay unchanged.
  `panel-composition` keeps this regression check; publisher retirement, invalid
  scalar values and failed/queued switches are covered by the unit checks.
- **[INFER]** A separate scalar read removes the snapshot wait from label updates
  in all compact modes. End-to-end key-to-render latency also includes IPC,
  compositor execution and frame scheduling; the isolated timer result does not
  measure those paths.

## Station indicator live workspace (2026-11-20)

- **[LIVE]** A standalone Quickshell probe on the installed session received
  `workspacev2` with `Hyprland.focusedMonitor.activeWorkspace.id` already at the new
  workspace in the same delivery. The older `workspace` event still carried the
  previous workspace. This is the source the bar label now reads in Station mode.
- **[LIVE]** Screenshots of the installed bar changed the number between 121 and
  178 ms after a native relative workspace switch (the follow-focus path), and within
  86 ms after an IPC station switch.
- **[SRC]** `StationBar` derives the number from the focused output's live workspace,
  so the display no longer waits for the 100 ms follow-focus debounce, the snapshot or
  the station batch. `currentStation` still waits for the compositor batch.
- **[QTTEST]** `grid.test.cjs` covers the live station, the out-of-map fallback, a
  Repetitive map and a missing map. `panel-composition` still covers the confirmed
  scalar fallback on the bridge and direct paths.
- **[LIVE]** After installing this change, the collapsed bar changed 一 to 二 in the
  first screenshot, 23 ms after a native relative workspace switch. The service's
  confirmed station followed at 157 ms. The switch was a synthetic Hyprland dispatch,
  so this measures the indicator path, not a physical key press.
