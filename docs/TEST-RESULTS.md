# Station v2 test results

Validated on 2026-10-05 with Omarchy 4 and Hyprland 0.56.x.

## Automated

- Compact-grid tests cover 81 transitions across one/two/three outputs and
  role orders, consecutive numbering, station preservation, overlapping source
  and destination IDs, partial-migration recovery, topology changes during
  recovery, window identity reuse, and the fixed-grid upgrade. Model tests cover
  display preference stability, fourth-display exclusion, direction, geometry,
  overlap detection, and exact mode selection.
- Service tests run the actual QML migration functions with a compositor double:
  no move before journal acknowledgment, no mapping publication before commit
  acknowledgment, failed saves/moves, shell restart with partial moves, removal
  grace, and a zero-display interval.
- Binding tests cover menu, `hyprctl`, and Lua conflict sources, modifier
  normalization, approved replacements, stale Station bind removal, custom
  actions, and unknown-source behavior.
- Monitor generator tests cover connector and exact-mode rejection, guarded
  disables, explicit mirror clearing, marker uniqueness, EOF placement,
  malformed marker refusal, plain geometry, and external-rule warnings.
- Recovery tests execute the detached cleanup template against a fixture and
  verify literal marker replacement and lease clearing. Static checks cover
  watchdog and Keep rollback requirements.
- Theme-token scanning reports zero literal palette values across all runtime
  QML, JS, and manifest sources. The Omarchy manifest validator passes.
- Both QML entry points compile against the installed `qs.Ui` and `qs.Commons`
  components.

## Live integration

- Service-owned IPC worked while the panel was closed.
- The Display-style panel rendered anchored below the Station bar widget with
  keyboard focus and outside/Esc dismissal.
- Station installed exactly 36 bindings. A shell restart kept the count at 36.
- Twenty physical `CTRL+SUPER+Left/Right` samples measured p50 66 ms and p95
  68 ms (range 64–69 ms).
- A no-change two-display preview created its watchdog token; Keep wrote a
  guarded block plus its plain copy, removed the token, reloaded cleanly, and
  preserved exact mode strings.
- Normal removal restored `omarchy.workspaces` to `left[1]`, restored the
  default `SUPER+1` binding, removed all Station bindings, cleared the persisted
  lease, replaced the managed block body with plain geometry, and left
  `hyprctl configerrors` empty.
- A shell `SIGKILL` during the M0 preview was recovered by the detached
  watchdog after about 20 seconds.
- Two cold compositor starts, one with HDMI and one laptop-only, returned an
  empty monitor list during `monitors.lua` evaluation and later discovered the
  expected displays without configuration errors. The guarded block and
  runtime service path reflect that result.

The fourth-independent-monitor case remains hardware-unavailable and is
documented as such in the accepted M0 gate. Physical unplug/replug and role
swap scenarios remain release-candidate manual tests because they move live
windows or require hardware interaction.

## Compact numbering revision (2026-10-05)

Ten automated test files pass; theme token and QML checks pass. QML probe still
logs the existing Qt portal registration warning. The local two-display upgrade
keeps station membership and records its committed mapping in workspace-map.json.
The live audit exposed old workspaces placed on the wrong monitor; the legacy
upgrade now preserves their actual physical display instead of trusting the old
slot-to-monitor assignment.

Physical unplug/replug and real Single/Extend round trips for this new algorithm
remain to be tested by the user. Three-display coverage is simulated, not a
claim of a three-monitor hardware test. The v1-style directional-key sequence is now ported and covered by service tests
for native tile/monitor movement, vertical and horizontal station boundaries,
Single mode, RTL, closed windows, topology cancellation, numbered sends, and
silent sends. The user confirmed the repaired keybindings and arrow behavior
with real keys on 2026-10-05.

## Layout drag repair (2026-10-05)

The original drag handler was reproduced in Qt's offscreen pointer harness:
its first X write rebuilt the Repeater and destroyed the card, causing
`ReferenceError: root is not defined` before the Y write and Preview.
The replacement commits both coordinates atomically from the canvas, derives
pointer offsets without losing the drag-threshold distance, uses screen-pixel
edge snapping, and fits the available canvas with space for both orientations.
Selected resolution, scale and rotation determine the displayed logical size.

`python3 tools/v2/check-layout.py` runs the production layout component,
Model.js geometry and extracted Service.qml position setter, with theme paint
and Preview compositor calls doubled. Ten cases pass (12 QtTest passes
including setup/cleanup), without warnings: horizontal right/left (including
negative coordinates), vertical, click-only selection, repeated drag after Revert, nearby
edge snapping, selected-mode/scale/rotation geometry, three-display fit, and
invalid/busy position rejection. The CI workflow includes this check.

After the first live test failed, the harness was corrected to put the layout
inside the same kind of scrolling `Flickable` used by the panel. That reproduced
the reset: the parent stole the pointer grab and canceled every drag. The
monitor-card `MouseArea` now prevents stealing; the additional vertical-scroll
regression passes and confirms that the panel does not scroll during a monitor
drag.

All ten Node test files pass; theme checking scans 13 runtime sources with zero
violations; manifest validation and QML compilation pass. The Wayland QML
probe still emits the existing Qt portal registration warning.
Physical GUI drag/Keep confirmation remains for the user; these tests do not
alter the live monitor arrangement.
