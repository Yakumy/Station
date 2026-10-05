# Station v2 architecture

Station is loaded twice by Omarchy: `Service.qml` owns persistent behavior and
IPC, while `Panel.qml` is the bar widget and Display-style popout. The panel
reads the injected service object and contains no workspace policy.

The service keeps five operation states: `idle`, `applyingLayout`,
`previewing`, `reconciling`, and `switching`. Each operation captures a
generation. Delayed work and process callbacks stop when that generation is no
longer current. Expected monitor and workspace events are recorded before a
Station-generated Hyprland evaluation so those events cannot trigger a second
topology operation.

Pure modules under `lib/` isolate policy from QML:

- `Model.js` owns the 10×3 workspace grid, stable lane assignment, present
  sets, reconciliation, role swaps, navigation, monitor geometry, and exact
  display mode selection.
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

The Keep path writes candidates inside Station's state directory, backs up
`monitors.lua`, atomically replaces it, reloads Hyprland, and checks
`hyprctl configerrors`. Failure restores the backup. Disable and removal start
a detached cleanup that waits through shell restart, distinguishes a still
enabled plugin, restores the stock widget, replaces mode rules with plain
geometry, clears the lease, and reloads Hyprland.
