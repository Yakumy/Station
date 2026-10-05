# Station v2 architecture

Station is loaded twice by Omarchy: `Service.qml` owns persistent behavior and
IPC, while `Panel.qml` is the bar widget and Display-style popout. The panel
reads the injected service object and contains no workspace policy.

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
- `Hypr.js` validates connectors, addresses, and workspace numbers before
  producing Lua. It is the only module that generates workspace and window
  dispatches.
- `Binds.js` defines actions, normalizes key combinations, parses conflict
  sources, and emits idempotent runtime bindings.
- `MonitorsLua.js` validates layouts and produces the guarded managed block and
  geometry-only cleanup copy.
- `Store.js` owns versioned defaults and bounded migrations.
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
`monitors.lua`, atomically replaces it, reloads Hyprland, and checks
`hyprctl configerrors`. Failure restores the backup. Disable and removal start
a detached cleanup that waits through shell restart, distinguishes a still
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
