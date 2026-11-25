<!-- summary: Switching, sending and moving windows, direction, starting station, Omarchy renumbering (workspace authority), follow focus, compositor events. -->
<!-- code: lib/stations/Station* lib/stations/*Authority* lib/platform/Events.js lib/platform/Compositor* Service.qml -->
# Station actions and events

## Direction

`config.direction` is `ltr`, `rtl`, `ttb` or `btt`. It maps a physical arrow key to a
station step on one axis and returns no step on the other axis.

## Switch

Apply rules for the map, focus each output's workspace, and finish on the previously
focused output. One eval batch does all of this.

Numbered requests during a switch keep the latest target and return `queued`. That
target runs after the batch if the map is still ready. A topology operation drops it.
Preview, migration and window moves return `busy`. A Lua error response must not update
the saved station, even if the process exits successfully.

## Send

`SUPER + SHIFT + n` sends to the same output on station n and follows.
`SUPER + SHIFT + ALT + n` sends without following. Numbered sends also accept an
unpinned active window in Omarchy's `special:scratchpad` (`SUPER + S`) or its Quake
console, `special:qconsole` (`SUPER + grave`), on a managed output, as Omarchy's own
numbered move does. Other special, named, pinned and unmanaged windows stay excluded,
and automatic migrations and directional moves never take scratchpad or console
windows.

## Move across

For `SUPER + SHIFT + CTRL + arrow`:

1. Read the actual active window from `hyprctl activewindow -j`, never a cached focus
   entry.
2. Try native directional movement. Wait 20 ms. Read that window again by identity.
3. If its position, size, workspace or monitor changed, native movement won. In
   Station mode, accept a monitor crossing only to the directional neighbor below;
   correct any other crossing using the source window's station and output.
4. Otherwise try the neighboring managed output in that physical direction. A
   neighbor must share a positive logical span perpendicular to the arrow, accounting
   for scale and rotation. Side-by-side outputs with different heights are not
   up/down neighbors, and corner contact alone is not enough.
5. At an outer edge, step one station. Keep the output when crossing perpendicular to
   the arrangement. Enter the opposite-edge output when crossing along it.
6. Synchronize every output in the destination station and focus the moved window.

For example, with side-by-side outputs and BTT, Up at the top tile of Station 3
reaches Station 4 on the same output. Down reaches Station 2 there. TTB reverses
these station steps. At Station 1 or 10, an invalid native crossing returns to the
source station and output.

A reconnected output can retain an unrelated active workspace. If a native move crosses
an output boundary, the window must keep its source station.

## Starting station

A login starts on Station 1, whatever was open at shutdown. Station keeps the
`HYPRLAND_INSTANCE_SIGNATURE` it last started under in `~/.local/state/omarchy/station/session`.
A different or missing signature means a new login. The same one means a shell restart,
which keeps the station whose workspace is focused, and the saved `lastStation` when the
focused workspace is outside the map. The focused workspace alone cannot tell a login:
Hyprland's first workspaces and what the shell sees at login are not reliably Station 1.

## Workspace authority

Omarchy 4.5 gives each monitor its own block of ten workspaces and reconciles them on
every reload and hotplug. Station's grid and those blocks disagree about what a number
means, so the reconcile renumbers station workspaces.

Station writes `~/.local/state/omarchy/toggles/hypr/station-workspaces.lua`, which
replaces `o.workspaces.reconcile` with a no-op. It must be a file, because a reload runs
the reconcile before any shell event arrives. Station also evaluates the same line at
startup, because the running configuration predates the file. Removal cleanup deletes
the file and reloads, which hands numbering back to Omarchy. A shell restart does
neither.

Repetitive is Omarchy's own numbering, so a committed Repetitive map with `blocks`
releases the authority: the file and the evaluated line put back the reconcile that
arming kept aside in `o.workspaces.station_reconcile`. Omarchy then renumbers, moves
and returns windows on reload and hotplug exactly as without Station, and Station's
migration between two Repetitive maps moves no window. Leaving Repetitive arms it again.

## Follow focus

Station mode only. When enabled (the default), a focused workspace change on a managed output switches
the whole station, after a 100 ms debounce. It acts only in `idle`, with no topology
change in the last 500 ms, and re-reads state first. Station-generated events never
trigger it.

## Events

- Record `expect` before any eval that causes monitor or workspace events. Matching
  events never start a topology operation or follow focus.
- `configreloaded`: count a new generation and clear applied binds. In `applyingLayout`,
  do nothing more. In `previewing`, cancel the preview. Otherwise debounce 300 ms and
  re-run observation, binds and reconciliation. The debounce exists because
  `omarchy theme set` fires the event twice.
- `monitoradded`: cancel removal grace, refresh and reconcile. The panel does not open.
- `monitorremoved`: keep the old map during `graceMs` (default 0, no delay). A reconnect
  cancels compaction. Afterward, run a journaled migration.
- A real topology event during `previewing` cancels the preview. A removal during
  `switching` aborts the switch. During `migrating`, it marks the topology dirty.
- Station ignores workspace events during topology changes. An unplug can create a
  spare workspace for a moment.
- A successful watched apply must not force a second reload or replay monitor rules.
