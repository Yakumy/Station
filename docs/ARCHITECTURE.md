# Station v2 architecture

Omarchy loads one persistent `Service.qml` for behavior and IPC, and a
`Panel.qml` bar widget and Display-style popout per output. Under the trusted
built-in bar, the panel reads the service directly. Replacement bars receive a
service-less facade, so the panel falls back to `BarServiceProxy.qml` and
`WallpaperProxy.qml`: detached snapshots and closed, validated service actions
published through `lib/BarBridge.js`. There is no second service or workspace
policy in the widget. The wallpaper controller itself never crosses the bridge
because its `station` property points back to the service.

`Panel.qml` and `Service.qml` import the bridge from the same directory. The entry
passes a reader callback into `StationPanel.qml`; importing the script directly
from that nested QML type creates a separate `qs:///` library in Quickshell,
while the service uses `file:///`. Only the replacement-bar path polls (250 ms
open, 1 s closed); unchanged snapshots do not emit property changes. Panel intent
writes use service setters on both paths. Deferred popout settlement captures
the persistent API and scalar transfer deadline rather than a proxy destroyed
by a bar rebuild.
`StationBar.qml` keeps the logo and unbracketed station label in separate host
buttons, arranged as a row on top/bottom bars and a column on left/right bars.
Its painted geometry follows the Omarchy menu glyph metrics; `StationMark.qml`
shares the themed SVG mark between the bar and panel header.

Station 2.2 also declares a full-bar entry. `Bar.qml` creates one
`MonitorBar.qml` instance per connected Quickshell screen and passes each a
detached copy of the shared layout with that connector's saved position,
width, thickness, background mode, and surface style.
The wrapper coordinates popouts across those isolated copies so opening a
panel on one output closes the panel already open on another.
Presence, position, width, height, content size, background, and style live in both Station's
validated `config.bars` preferences and the shell bar's `monitors` map. While
the panel is open, the full bar reads
the detached `config.bars` snapshot through the top-level bridge and treats it
as the live authority; the service defers the redundant shell map write until
the panel closes. This prevents an otherwise harmless host config reload from
recreating the third-party bar and its panel mid-click. The service refuses to
hide the last bar on an enabled output.
The default style paints one continuous surface. Pill style paints independently
rounded left, center, and right islands while reusing the selected Background
mode; its padding is included in each live bar's non-overlap measurement.
For Pill, Blur, and Transparent presentations, `MonitorBar` expands only its
visual/input layer inward by `Style.gapsOut` and keeps the exclusion zone at the
configured thickness. Omarchy defines that token as half Hyprland's outer
window gap, which centers module icons in the complete monitor-edge-to-window
strip without moving tiled windows. Solid default bars retain stock geometry.
Pill end islands additionally use the full outer gap (`Style.gapsOut * 2`) on
the bar's parallel monitor edges. The panel's cross-axis stabilization permits
the half-gap visual extension when validating the remapped bar window; the
exclusive-zone size exposed to popup placement remains unchanged.
Content size is stored per monitor as a font-pixel target. Above the default,
`MonitorBar` renders each module as a uniform zoom of its default-size subtree
at the requested-to-default ratio — the same proportions as Omarchy's global
text size, scoped to that one bar. Native-rendered text and font icons switch
to Qt's scalable distance-field rendering while zoomed, restoring their original
render type at default size. Enlarging an offscreen layer does not re-rasterize
native glyph caches, so the loaders render directly without that extra layer.
The bar also multiplies each loaded image's `sourceSize` by the same ratio.
Existing tray effect-source and tray-group layers receive matching physical-pixel
texture sizes, bound to their geometry and output pixel ratio; otherwise those
intermediate textures downsample the decoded images before enlargement. Their
original texture sizes are restored at default content size. StationMark uses
Qt Quick curve-rendered vector paths from the supplied SVG geometry, with the
foreground tint applied directly. Its bar placement follows a centered Text
reference matching the Omarchy menu button, including its actual baseline.
The along-bar slot grows by that ratio so module gaps keep their proportions.
The live maximum preserves `Style.spacing.sm` on both cross-axis edges and
checks the scaled left, centered, and right extents against the monitor length.
Each bar reports that maximum through the detached bridge together with its
minimum width. The tray slot removes Omarchy's unpainted collapsed drawer
reserve from its flow extent and adds it back as the reveal animation advances,
so the Pill island follows the visible tray. A zero stored value
follows Omarchy's live `Style.font.body` default.
Blur is compositor-owned. The service keeps a persisted lease of the prior
global Hyprland blur state, enables one named layer rule for the shared
`omarchy-bar` namespace, temporarily uses size 8 with three passes, and
restores the prior global enabled/size/pass values after the final connected
Blur bar changes mode. Fully transparent surface regions are
excluded, which matters because partial bars retain a full-screen coordinate
surface for correct popup anchoring.
When Station becomes the active full bar, the service atomically removes its
persisted widget row and `MonitorBar` supplies a virtual copy beside the menu.
The service also reconciles that row on activation, covering upgrades where
Omarchy selects the new full-bar kind before the user makes a Bar-tab edit.
This avoids Omarchy's multi-kind disable ambiguity: resetting the full-bar id
then removes the last enable reference and unloads the service normally.
The bundled bar is an MIT-licensed adaptation of Omarchy 4.0.6; provenance is
recorded in `THIRD_PARTY_NOTICES.md`.

`BindingKeyPicker.qml` captures allowlisted key events and offers a static
special-key menu. It updates only the binding draft; Apply retains the existing
service validation and conflict policy. Station creates no editable text
controls, avoiding Qt's automatic clipboard retrieval on clipboard changes.

The service keeps six operation states: `idle`, `applyingLayout`,
`previewing`, `migrating`, `moving`, and `switching`. Switching uses generations to
discard stale callbacks. Migration is serialized and blocks window commands;
topology changes during a migration trigger replanning from its journal. Expected monitor and workspace events are recorded before a
Station-generated Hyprland evaluation so those events cannot trigger a second
topology operation.

Pure modules under `lib/` isolate policy from QML:

- `Grid.js` owns compact numbering, active output order, address-based migration
  plans, interrupted-migration recovery, and station existence. A saved mapping
  determines how to decode existing IDs; current hardware never retroactively
  determines their meaning.
- `Model.js` owns stable display preferences, monitor-ID normalization, direction
  navigation, monitor geometry, and exact display mode selection.
- `PanelPosition.js` computes the host KeyboardPanel gap needed to center the
  panel card on the selected output while keeping its existing focus and
  dismissal behavior.
- `Hypr.js` validates connectors, addresses, and workspace numbers before
  producing Lua. It is the only module that generates workspace and window
  dispatches.
- `Binds.js` defines actions, normalizes key combinations, parses conflict
  sources, and emits idempotent runtime bindings.
- `MonitorsLua.js` validates layouts and produces the guarded managed block and
  geometry-only cleanup copy. If cold discovery is empty or the saved survivor
  is absent, an exclusive fallback applies saved geometry with outputs enabled
  and unmirrored. Warm reload executes only the combined final-state rules, so
  a disabled output is not briefly re-enabled by a geometry prepass.
- `Store.js` owns versioned defaults and bounded migrations.
- `Wallpaper.js` validates wallpaper preferences and owns logical crop geometry,
  native-resolution recommendations, and theme/background profile resolution.
  `WallpaperController.qml`, owned by the persistent service, retains the draft
  and opens Omarchy's native file chooser. A picker result is never assigned to
  a QML Image: the fixed-argv `SanitizeWallpaper.pl` helper first streams it into
  a fresh private directory with input, PNG chunk-count, and raster bounds. The
  helper recognizes content rather than extensions and retains only bounded PNG
  rendering chunks, so compressed text/profile metadata is never decoded in the
  shared shell. Perl is an Omarchy package dependency; the helper uses only core
  modules and is not an image decoder. Previously saved unmarked local choices
  remain hidden while they pass through the same boundary. The controller then
  validates safe image decoding, snapshots source files, and saves
  `config.wallpaper`. Success waits for the config FileView save acknowledgment;
  failure restores the previous in-memory wallpaper settings.
  `WallpaperLayout.qml` and desktop `WallpaperImage.qml` share the same crop
  transform. Click-through, keyboard-unfocused bottom-layer surfaces sit above
  Omarchy's stock background and disappear with the service. The default same-image
  theme mode leaves the stock surface visible. After a committed or reverted display
  topology change, `ScreenHealth.js` compares enabled, non-mirrored Hyprland outputs
  with Quickshell's screen list. A missing screen means the host lost every surface
  for that output. After the preview token is gone, and only when another active
  output remains visible to the shell, Station cycles the missing output once and
  restores its validated exact rule. No theme hooks or external daemon are
  installed. A 1.5-second read-only poll observes the current theme/background;
  theme changes invalidate an unfinished snapshot job while following Omarchy.
- `Transactions.js` and `Recovery.js` contain fixed shell templates. Dynamic
  values reach them only as validated positional arguments.

Station stores user preferences separately from runtime bookkeeping. Display
identity and preferred lanes live in `config.json`; the last station, applied
bindings, stock-widget lease, and lifecycle flags live in `state.json`.

`workspace-map.json` contains the committed mapping and any pending migration.
The service waits for the FileView saved signal before executing a migration.
It applies workspace rules, moves the snapshotted window addresses, places
existing destination workspaces on their outputs, then verifies live results.
Only after the commit write succeeds does it expose the new mapping to window
commands. A failed move or interrupted shell keeps the old mapping and journal;
a restart retries the same logical destinations, matching address, PID, and
initial class. It never decodes partially migrated IDs as a fresh source map.

Snapshot requests are queued so concurrent topology and focus events cannot
replace a migration callback. Removal grace retains the old map; adding a
monitor before the grace expires cancels compaction. The first upgrade from
state version 1 explicitly decodes the previous three-slot grid.

The Keep path writes candidates inside Station's state directory, backs up
`monitors.lua`, atomically replaces it, lets Hyprland's file watcher apply it,
and checks `hyprctl configerrors`. Failure restores the backup and reloads
Hyprland for recovery. Disable and removal start a detached cleanup that waits
through shell restart, distinguishes a still
enabled plugin, restores the stock widget, replaces mode rules with plain
geometry, clears the lease, and reloads Hyprland.

Window actions read `hyprctl activewindow -j` after refreshing monitor state, so
they do not rely on a cached focus-history entry. Directional actions execute
the v1 native directional dispatcher, wait 20 ms, then re-read the same window
by address/PID/class. If its position, size, monitor or workspace changed, native
movement won; otherwise geometry and station-edge fallback apply. Generations
cancel stale fallback after topology changes. Follow moves focus every output
in the destination station, finish on the moved window's output, and explicitly
focus its address. Silent moves leave the selected station alone.

`lastWindowAction` in the existing status IPC records reception, selected address,
and completion result for diagnosing real keys without synthetic input.
