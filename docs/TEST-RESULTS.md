# Station v2 test results

## Single eDP panel evacuation — 2026-10-27

- Live state showed a healthy Extend topology and journal, with Single eDP
  aborting only at the HDMI panel-close acknowledgement. The same transition
  completed when reproduced immediately afterward.
- The replacement bar can switch from its 250 ms open-panel bridge poll to a
  1000 ms closed-panel poll before the 180 ms unmap acknowledgement. The safety
  timeout now provides 2.5 seconds, with a regression test enforcing margin.

## Mirror role-source migration — 2026-10-27

- Live state captured HDMI-A-2 saved as role 1 while it remained the mirrored
  sink of eDP-1. The resulting eDP-1-to-HDMI-A-2 journal could not place either
  workspace and blocked every later display action.
- Role swaps now apply the new Mirror source/sink topology before reconciling
  the compact workspace map. A transaction test asserts source activation,
  sink mirroring, then migration in that order.

## Mirror source to Single sink migration — 2026-10-27

- Live reproduction confirmed that detaching the mirrored eDP-1 sink, focusing
  it, and moving the recorded workspaces are each accepted by Hyprland.
- Migration now checks workspace-rule installation separately and always reads
  back window destinations after the move batch. A compositor double covers an
  aggregate rejected result after all destinations were actually applied.

## Mirror editor geometry — 2026-10-27

- Live Mirror state reported eDP-1 and HDMI-A-2 at the same `0x300` runtime
  coordinates while Station's managed block still retained eDP-1 at `1920x0`.
- Strict managed-block parsing now restores the independent saved geometry to the
  editor and rejects malformed or conflicting duplicates. A service-level test
  covers the collapsed runtime snapshot without changing Mirror compositor state.

## Post-topology shell screen recovery — 2026-10-27

- Live diagnosis found both outputs enabled in Hyprland, but no background or bar
  layer on eDP-1; the shell log recorded a dangling Qt screen object and an
  untracked eDP-1 removal. A fresh shell and a Hyprland reload still exposed only
  HDMI-A-2 to Qt. Cycling only eDP-1 restored its exact saved rule and both missing
  layers without restarting the shell.
- The pure screen-health tests cover a missing active output and exclude disabled
  and mirrored outputs. They also refuse recovery without a healthy survivor. A
  source-contract test keeps the single output cycle after settled Keep or Revert
  and out of the active preview interval.
- All 202 Node/M0 tests and all 23 offscreen layout cases pass. Theme-token
  scanning reports 36 source files with zero violations, and live-Wayland QML
  compilation passes.

## Unequal-height side placement — 2026-10-24

- Edge attachment and parallel-edge alignment now use distinct snap thresholds.
  A broad screen-space edge snap keeps monitors connected, while the cross axis
  stays at any 10-unit grid offset unless it is within 20 logical units of exact
  top/bottom or left/right alignment.
- Pure geometry tests cover a 1920×1200 monitor at the centered −60 offset beside
  a 1920×1080 monitor and retain exact top/bottom alignment. The production
  pointer harness performs the corresponding attached drag and verifies the
  saved coordinates and non-overlap. Physical drag acceptance remains a user
  check after installation.
- All 172 Node/M0 tests pass. Displays/Bar passes 22/22 offscreen cases,
  Wallpaper passes 10/10, Station bar passes 26/26, and the theme scan reports
  35 source files with zero violations. Clean-package validation, live-Wayland
  QML compilation, and whitespace checks pass.

## Scale adjacency repair — 2026-10-24

- Direct Scale and Resolution changes now preserve the strongest shared edge
  before saving, publishing the new logical size and corrected position
  together. Scaling either side of an attached pair remains non-overlapping and
  pointer-connected without adding a Keep/Revert preview.
- Transaction coverage verifies both left and right display scaling, one watched
  apply, no forced reload, exact edge contact, and no overlap. Pure geometry
  coverage also exercises the shared resize rule used by rotation. Physical
  compositor and pointer acceptance remain a user check after installation.
- All 172 Node/M0 tests pass. Displays/Bar passes 21/21 offscreen cases,
  Wallpaper passes 10/10, Station bar passes 26/26, and the theme scan reports
  35 source files with zero violations. Clean-package validation, live-Wayland
  QML compilation, and whitespace checks pass.

## Rotation adjacency repair — 2026-10-24

- Rotation preserves the strongest shared monitor edge and atomically publishes
  its corrected position with the new transform. A rotated monitor therefore
  stays attached instead of overlapping or separating from its neighbor.
- Pure geometry coverage includes horizontal adjacency and the reported
  1920×1200 monitor above a 1920×1080 monitor. The production offscreen pointer
  harness exercises the service update through the real rotation controls and
  checks that both arrangements remain touching and non-overlapping. Physical
  compositor acceptance remains a user check after installation.
- All 171 Node/M0 tests pass. The Displays/Bar offscreen harness passes 21/21,
  Wallpaper passes 10/10, Station bar passes 26/26, and the theme scan reports
  35 source files with zero violations. Clean-package validation, live-Wayland
  QML compilation, and whitespace checks pass.

## Monitor-card presentation gaps — 2026-10-24

- Displays and Bar now inset each painted monitor card by half of
  `Style.spacing.sm` (doubled from the initial `xxs` after visual review), so
  logically touching outputs retain a compact named
  theme-space gap without changing their saved geometry. Same and Per monitor
  Wallpaper previews use the same gap; Span remains exactly edge-to-edge so its
  continuous image crop is unchanged.
- All 170 Node/M0 tests pass. The offscreen Displays/Bar geometry harness passes
  20/20 cases, including exact adjacent-card gap coverage; the Wallpaper harness
  passes 10/10, including separate contiguous Span and gapped non-Span checks.
  The Station bar harness passes 26/26.
- Theme scanning reports 35 source files and zero violations. A clean tracked-file
  package passes plugin validation, live-Wayland QML component compilation
  reaches `STATION_COMPONENTS_READY`, and whitespace checks pass. Direct checkout
  validation still encounters the documented ignored
  `videos/intro/node_modules` symlink. Final visual acceptance remains a user
  check after installation; no live monitor topology was changed by these tests.

## Bar side change without a panel reload — 2026-10-23

- Finding: the stock-adapted `MonitorBar` swapped `root.vertical`-keyed Loader
  components for the section container, the center arrangement, and every module
  Row/Column. A top→left/bottom→right-style axis flip therefore destroyed every
  module slot — the Station widget and the open popout with them — and the
  pre-armed hand-off reopened the panel, which read as a reload. Same-axis flips
  (top↔bottom, left↔right) kept `vertical` unchanged and rebuilt nothing. The
  per-monitor asymmetry (reload seen on eDP-1, not on HDMI-A-2) followed from the
  open panel being hosted on eDP-1: only the edited monitor's bar touched the
  panel-host copy.
- Repair: one always-present section arrangement plus one orientation-agnostic
  synchronous positioner per region now host the same module instances in all
  four positions; the placement math lives in `lib/BarModel.positionModules`
  with unit tests, including skips for invisible slots and reflow across flips.
  A side change reflows those instances in place. Follow-up live testing found
  a second, intermittent host-level path: some `shell.json` position writes
  recreated both full-bar surfaces and their widget populations even though
  the inner layout was stable. The installed log showed changed layer-surface
  addresses, duplicate IPC registration, and callbacks evaluated against
  invalid old `MonitorBar` contexts. `Bar.qml` therefore reads the service's
  detached `config.bars` snapshot as the live authority while the panel is
  open; the service batches and defers the redundant `shell.json` monitor-map
  mirror until the panel closes. The §10.3 hand-off remains armed as a fallback
  for genuinely structural rebuilds.
  Module positions now come from the positioner on entries/vertical/size
  changes; module drag-reorder and popout geometry read live slot geometry as
  before.
- Checks after the geometry-gating follow-up: 169 Node/M0 tests (including the
  new positioner, open-panel deferral, one-write flush, bridge-precedence, and
  retained-screen and geometry-gating coverage), `check-bar-layout.py` 26/26,
  display pointer harness 18, theme tokens 0 violations, live-Wayland QML
  compilation, and whitespace checks pass. Live acceptance of flips on both
  monitors (panel open, no host-surface replacement before close, tab retention,
  drag reorder, hover, tray drawer, center anchor) remains a user check.

- Follow-up after physical acceptance: same-axis moves remained clean, while
  horizontal↔vertical moves still produced a shorter panel glitch after the
  host-write deferral. The panel now retains its Quickshell screen object while
  open. A second physical check showed that was insufficient: moving the other
  monitor's bar is clean, while changing the panel-owning bar still glitches.
  The panel now also withholds the new logical edge until its anchor window has
  changed to the matching horizontal or vertical geometry, preventing a frame
  that combines the new edge with the old full-axis dimension. Source coverage
  verifies the retained-screen and geometry-gating paths; repeated physical
  cross-axis acceptance remains pending.

## Per-monitor bar control — 2026-10-22 (2.2.0)

- All 157 Node/M0 tests pass, including config migration, full-bar manifest,
  last-visible-bar protection, read-only monitor geometry, all four positions,
  panel-tab restoration, and bridge allowlist coverage.
- The existing bar geometry harness passes all 26 position/font/station cases;
  the display pointer harness passes all 18 cases with its existing incomplete
  theme-stub warnings.
- The production Bar tab renders against the installed Omarchy UI modules with
  the connected and disabled monitor examples, all four arrows, bar previews,
  the central switches, and the intentionally empty right panel; no QML layout
  or binding warnings are emitted. Displays, Bar, and Wallpaper now fit the
  actual monitor union with a 10% default canvas inset. Bar previews remain at
  58% of one side, disappear when off, and leave no accented arrow when off.
- Theme-token scanning, live-Wayland compilation of every QML component,
  clean-package manifest validation, and whitespace checks pass.
- The full-bar entry is an MIT-attributed adaptation of Omarchy 4.0.6. Commit
  `25f0627` was installed and active on the two-monitor system; the user
  confirmed independent per-monitor position and presence controls work.
  A live stock-versus-Station comparison measured identical reserved thickness:
  26 logical pixels horizontally and 28 vertically, with matching icon/menu
  centering. The UI refinements and Bar-tab restoration remain user acceptance
  checks; hotplug and disable/remove behavior remain outside this check.

## Bar alignment and vertical indicator — 2026-10-22 (2.1.9)

- All 150 Node/M0 regression tests pass with normal local process access.
  The two Lua subprocess files fail under the restricted sandbox, as before.
- New `python3 tools/v2/check-bar-layout.py` harness: 24 combinations of
  top/bottom/left/right, font sizes 10/12/18, and S1/S10 pass, plus setup/cleanup.
  It exercises production StationBar and the installed host WidgetButton,
  checks painted alignment and gaps, vertical bounds, and both click targets.
- Existing Displays pointer harness: 18 pass, with existing incomplete theme
  stub warnings. Theme tokens and live-Wayland QML compilation pass.
- Direct checkout validation encounters ignored video `node_modules` symlinks;
  validate a clean tracked-file package instead of modifying those local files.
- Live visual acceptance, including side-bar rebuilds, remains with the user.

## Replacement-bar bridge — 2026-10-20

- All 150 Node/M0 tests pass, including detached snapshot, closed action
  allowlist, proxy coverage, stale-service retirement, and panel hand-off tests.
  The two Lua subprocess files timed out under the restricted execution sandbox
  and passed when rerun with normal local process access.
- All 18 offscreen Displays tests pass. Theme-token scanning, manifest
  validation, live-Wayland component compilation, and whitespace checks pass.
- The reviewed PR commit was installed through the stock plugin updater. Station
  remained healthy under the stock bar and under Pill Bar (`bit-dev.bar`), a
  third-party replacement bar using Omarchy's service-less entry facade. The
  user confirmed Station's panel and controls worked with the replacement bar
  on the live two-monitor system.
- This confirms the replacement-bar bridge and ordinary panel interaction on
  the tested two-monitor system. Simultaneous hotplug, three/four-monitor
  hardware, and every Single/Mirror transition remain outside this check.

## Wallpaper — 2026-10-11

- Node suite: 129 tests, including wallpaper geometry, profile recall, input
  validation, copy failure, stale completion, preference-save failure, literal
  hostile filenames, and exclusive snapshot publication. The existing Lua
  subprocess tests require execution outside the sandbox on this machine.
- Offscreen Wallpaper pointer/renderer harness exercises
  production QML, verifies fixed-group movement and zoom, and samples the actual
  rendered crops for two adjacent outputs. It also verifies that an Apply-style
  switch to an identical saved copy retains every monitor's preview coordinates.
  Existing Displays harness: 18 pass.
- Theme-token scan: 25 sources, zero violations. Manifest validation, QML
  compilation against installed modules, and whitespace checks pass.
- Isolated production tab renders were inspected with dark and light palettes
  using the installed components. No theme, monitor layout, or user wallpaper
  was changed by these probes. The live monitor snapshot confirms the current
  stacked pair's Fit recommendation is 1920×2280.
- Full native chooser interaction, physical hotplug with wallpaper active,
  shell-restart persistence of a user-selected wallpaper, actual theme switching,
  and three-display hardware remain user acceptance tests. Automated geometry
  and mocked lifecycle checks do not establish those hardware results.

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
invalid/busy position rejection.

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
space it needs. A static test guards the fixed, non-scrollable structure.

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

## Clipboard-free binding picker (2026-10-13)

The conflict editor no longer instantiates a native text input, including in
hidden rows. `BindingKeyPicker.qml` uses key events and a static special-key
menu; modifiers remain explicit chips and saving remains an explicit Apply.
The editor wraps its controls when space is limited.

Validation on Qt 6.11.2 / Omarchy 4.0.3: all 133 Node tests pass, including a
runtime-source guard against editable input/clipboard APIs. The new
`python3 tools/v2/check-binding-picker.py` offscreen harness reports 14 QtTest
passes (including setup/cleanup), covering letters, digits, arrows, function
keys, punctuation, Return/Space, modifiers, cancellation, Tab, focus/visibility
loss, unavailable state and the actual special-key popup. Host button paint is
doubled; production capture and popup handlers run unchanged. The existing
layout harness reports 18 passes; theme checking (26 sources), manifest
validation, installed-host QML compilation and whitespace checking pass.

Node's Lua subprocess tests required execution outside this sandbox after
stdin delivery timed out inside it. QML compilation requires Wayland access. These
checks do not prove physical Hyprland binding delivery or reproduce a hostile
clipboard provider on the reviewer's Qt 6.12.0 package.

## Bounded wallpaper import (2026-10-13)

Foreign picker results no longer enter a QML Image before Apply. A fixed-argv,
core-Perl helper recognizes content by magic bytes, streams a private snapshot,
and reduces PNGs to bounded rendering chunks without decompressing text, ICC,
EXIF, or other ancillary metadata. The controller accepts only the helper's
Station-private output. Previously saved unmarked pinned images remain hidden
until the same staging and config-save sequence completes.

The regression fixture is a renamed 1×1 PNG under 32 KiB containing 24 zTXt
chunks that represent 12 MiB of expanded text. The test never submits the raw
fixture to Qt; it verifies removal of every zTXt chunk, byte-identical IDAT data,
private directory/file modes, content-based PNG detection, and failure cleanup.
Controller tests verify the raw picker path cannot change the draft, helper argv
separation, private-path enforcement, symlink rejection, legacy restaging, and
save acknowledgment. The complete Node/M0 suite reports 139 passes. The
wallpaper pointer harness reports 8 passes, the display layout harness reports
18 passes, theme scanning reports zero violations across 26 runtime sources,
and manifest validation, live-Wayland QML compilation, Perl syntax, and
whitespace checks pass. The QML check emits only the existing portal
registration warning.
