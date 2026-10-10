# Station v2 test results

## Cold-start geometry repair — 2026-10-10

All 119 Node/M0 tests pass, including real Lua evaluation of generated monitor
blocks with mocked cold, failed, missing-survivor and warm discovery. Warm
Single Keep tests still assert no output reannouncement. Theme scanning reports
zero violations across 20 runtime sources; manifest validation and
`git diff --check` pass. Lua subprocesses timed out inside the execution sandbox;
the isolated suite passed outside it. No live monitor changes or reboot were
performed for this verification. Existing saved blocks require regeneration
when installing this fix.

## Earlier validation

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

All eleven Node test files pass; theme checking scans 17 runtime sources with zero
violations; manifest validation and QML compilation pass. The Wayland QML
probe still emits the existing Qt portal registration warning.
The user confirmed physical horizontal and vertical drag/Keep behavior after
the ScrollView pointer-grab fix.

## Reference panel revision (2026-10-05)

The panel now follows `docs/v2/reference/panel.png`: fixed header and tab row,
global Mode and Direction dropdowns, a two-column Displays view, grouped
keybindings, and compact settings. The layout canvas has theme-token dots and
per-monitor rotation controls. There is no panel `ScrollView`, `Flickable`, or
`ListView`; content height follows the selected tab and the panel requests the
space it needs. A static CI test guards the fixed, non-scrollable structure.

All eleven Node test files, the 12-case Qt pointer suite, theme-token scan,
manifest validation, and component-by-component QML compilation pass. The QML
checker now compiles every runtime QML component instead of only the two entry
points.

## Panel sizing and preview restoration (2026-10-05)

Panel requested width increases from 680 to 748 theme units; fitted height is
multiplied by 1.1, within screen bounds. All six scale choices occupy one row
above Resolution/Refresh. Added the missing brightness debounce callback.

Manual Revert and timeout service regressions exercise the real QML functions
with delayed compositor snapshots. They confirm discarded geometry, scale and
mode reset only after fresh monitor data arrives, and runtime bindings are
invalidated and reapplied. All 12 Node test files and 12 Qt pointer cases pass;
the theme scan reports zero violations in 17 sources. Manifest validation and
QML compilation pass (the existing Qt portal registration warning remains).

## Layout canvas polish (2026-10-05)

The Displays columns now use a 65/35 split. The canvas grows to 228 theme
units high, with smaller cards and reserved arrangement space for up to three
monitors. Cards use an opaque popup surface and accent selection border;
background dots use reduced opacity and radius. Removed the panel's extra
10% height padding so its height follows content again, retaining its wider
width. Compact role labels fit the narrower settings column. All 12 Node
test files, 12 Qt pointer cases (including three displays), theme, manifest
and QML checks pass.

## Display-focused layout revision (2026-10-05)

The redundant display list is removed. Selecting a card in the layout canvas
now presents that display's connector, role, description, and enable control
at the top of the controls column. The canvas takes the full left-column
height. Its frame and the vertical column divider use the same subdued section
rule, while selected cards retain their accent outline. Mode and Direction use
Station-owned borderless dropdown triggers with the same text styling as the
top-level tabs. All automated checks continue to pass.

## Header and toolbar compactness (2026-10-05)

Mode and Direction triggers now size to their text and chevron, keeping both
inside the controls side of the layout divider. The panel has no outer content
padding, removing the unused top gap while retaining the header's own aligned
logo inset. The header subtitle now reports `v2.0.0` rather than the active
theme. Automated Node, Qt pointer, theme, manifest, and QML checks pass.

## Focused-panel monitor removal repair (2026-10-08)

The actual crash generated by selecting Single HDMI-A-2 was report 1041, not
the older report 1032 copy. Its stack is `CLayerSurface::onDestroy` →
`CLayerSurface::onUnmap` → `CInputManager::refocusLastWindow`, while the log
tail confirms `eDP-1` had just been disabled. Station now closes and unmaps an
open KeyboardPanel on the output being removed, waits for its acknowledgement,
enables a disabled destination when changing between Single targets, focuses
the survivor, and only then applies the output-removal rule. The target panel
is not reopened until that rule succeeds. Revert follows the same preparation
before reloading a saved Single/Mirror layout.

The service transaction double covers the reported `eDP-1` panel → Single
HDMI-A-2 sequence and asserts close → focus → disable order. It also covers
Single-to-Single destination activation and reverse rollback order: close →
enable saved output → focus saved output → reload. Panel tests guard the 180 ms
unmap acknowledgement and ensure it is not mistaken for user dismissal. All
16 Node/M0 suites, the 16-case Qt layout suite, and the theme-token scan pass.
Live reproduction was deliberately deferred until the installed plugin is
updated; physical confirmation remains pending.

## Optional stock Display-widget lease (2026-10-08)

Settings now exposes a default-off toggle for the preinstalled
`omarchy.monitor` bar widget. Automated coverage verifies config/state schema
migration, settings wiring, ownership-aware workspace and Display leases,
serialized bar-layout writes, panel transfer during either widget rebuild,
exact section/index restoration, and removal cleanup clearing both leases.
An interrupted restore is retried at the next service start when its setting is
off.

All 16 Node/M0 suites and the 16-case Qt layout suite pass. Theme scanning
reports zero violations across 19 runtime sources; manifest validation and the
Wayland QML component check pass. The QML check emits only the existing portal
registration warning. Physical toggle and uninstall restoration remain for
interactive confirmation.

## Direct display-side controls (2026-10-08)

Scale, Resolution, and Refresh no longer enter the topology preview or show
Keep/Revert. The service transaction double verifies that a Scale choice goes
straight from idle to the atomic candidate write, receives exactly one watched
configuration apply, returns to idle with the chosen value, creates no preview
journal/countdown, and never forces an additional reload. Layout drag,
rotation, Mode, and monitor on/off retain the preview watchdog and confirmation.

The live investigation also confirmed why Omarchy's stock Display scale
control reverted: its runtime `1.6` apply was followed by a generic-variable
edit of `monitors.lua`, whose later explicit per-output and Station rules still
declared scale `1`. The last rule won on autoreload. No packaged Omarchy source
was modified.

All 16 Node/M0 suites and the 16-case Qt layout suite pass. Theme scanning has
zero violations across 19 runtime sources; manifest validation and live-Wayland
QML compilation pass with only the existing portal registration warning.
