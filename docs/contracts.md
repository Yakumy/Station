# Contracts

This page states what Station must do and what it must never do. It describes current
behavior. If the code disagrees, one of them has a bug, so find out which. The
[platform findings](platform-findings.md) hold the evidence behind platform claims.

## What Station is

Station is a Quickshell plugin with QML, JavaScript, a little generated Lua and one
bounded Perl helper. It ships no compiled binary. Its one concept is the **station**:

- Switching a station switches every output together.
- Sending a window to a station keeps it on the same output.
- Unplugging an output merges its windows into a survivor without changing their
  station.

Station does not provide a standalone CLI, HDR, VRR or color management, self-update
logic, or management of more than three independent outputs.

## Principles

1. Install, update and removal use the stock `omarchy plugin` commands. Station makes
   no network access.
2. Station works when enabled. It has no setup step.
3. Station writes only its own files and its marked sections in `monitors.lua` and
   `looknfeel.lua`, always with a backup. Each file keeps its newest five Station
   backups (`<file>.bak.station.*`); a write removes older ones. It never edits `hyprland.lua`,
   `bindings.lua` or anything under `/usr/share/omarchy`.
4. Every value that reaches Lua or argv is validated.
5. Every asynchronous operation is checked against a generation.
6. The UI uses theme tokens only (see [Design system](design-system.md)).

## System authority

Hyprland and Omarchy own shared settings. Station observes them and persists only an
explicit edit.

| Setting | Authority | Station behavior |
| --- | --- | --- |
| Enablement, mirror source, geometry, scale, rotation, mode | Applied Hyprland state | Observe on reload, hotplug and every 1.5 s. Migrate workspace bookkeeping to the actual independent outputs. |
| Global gaps, Dwindle split, rounding, window animation speed | Hyprland options | Read on startup, reload and while the panel is open. Persist only an edited control. |
| Bar monitor rows, focused-monitor menu position | Omarchy shell config | Adopt changed rows. Discard superseded pending writes for those rows. |
| Global blur enabled, passes | Hyprland, except while a bar is set to Blur | Blur the user enabled stays untouched. While it is off and a bar is set to Blur, Station turns it on at runtime for that configuration, and returns the values it found when no bar wants it. Never written to a file. See [Bars](#bar-background-blur). |
| Global blur size | Hyprland | Never changed. |
| Personal keybindings | Hyprland and Omarchy bindings | Report conflicts. Do not replace personal binds without approval. |
| Wallpaper | Omarchy under Follow, otherwise Station's explicit choice | See [Wallpaper](#wallpaper). |
| Brightness, text size | Omarchy commands | Connector-specific reads and writes. |
| Workspace numbering | Station while enabled | Omarchy's per-monitor reconcile is off. See [Workspace authority](#workspace-authority). |
| Station IDs, lanes, journal, UI preferences | Station | Persist and recover independently. |

Consequences:

- A runtime change from a terminal appears in Station but is not written to a Lua file.
  A later reload applies the files normally.
- `config.json` may cache observed display values, but they never enforce state.
- DPMS or screen blanking is not disablement.
- A mirrored sink never receives a workspace column, even when the source has a higher
  lane.

## Concepts that must stay separate

| Concept | Meaning | Stored |
| --- | --- | --- |
| Identity | Key from `description`. If two connected monitors share it, append `@<connector>`. | `config.json` |
| Lane (1 to 3) | Preferred order of an output | `config.json` |
| Slot | Current dense index in the committed map | `workspace-map.json` |
| Role | Displayed ordinal of a lane among those present | Never |

With lanes 1 and 3 present, the panel shows roles Primary and Secondary, and the slots
are 1 and 2.

## Workspace numbering

For the ordered active outputs and `N = outputs.length`:

```text
workspace(station, output) = (station - 1) * N + index(output) + 1
stationOf(id, map)         = floor((id - 1) / map.outputs.length) + 1
```

There are ten stations and one to three active outputs. Single and Mirror have one
station-bearing output. Numbering has no holes: with two outputs, S1 is workspaces 1
and 2, and S2 is 3 and 4. Non-grid, named, special, pinned and unmanaged windows are
excluded from migration.

### Active map

- Extend uses the enabled managed outputs.
- Single uses its target, or a surviving fallback.
- Mirror uses its source.
- New outputs join Extend. Explicit Single keeps them out.
- A zero-output interval preserves the saved map.
- A station's meaning never changes retroactively: always decode existing IDs with the
  saved map, never with current hardware.

### Migration

1. Snapshot the clients before any move.
2. Decode each window's station and old output through the saved old map, even if
   Hyprland already moved its windows.
3. Keep each window's station, and its output if that output survives. Otherwise merge
   into the next surviving old output, then the previous one, then the new primary.
4. Persist a journal with old and new maps, and each window's address, PID, initial
   class, station and destination.
5. **Wait for the save acknowledgment before any move.** `FileView.setText` with
   identical text emits no new acknowledgment, so treat unchanged text as ready.
6. Apply workspace rules, then address-based moves, then place existing destination
   workspaces.
7. Snapshot and verify every live window. An aggregate dispatch failure does not prove
   failure, because an earlier move may already have applied.
8. Save the commit, and only then expose the new map to window commands.

Failed or interrupted work retains the journal. A restart resumes by window identity
and recorded station, never by decoding partly migrated IDs. If the topology changes
again, retarget the recorded logical destinations. Window commands wait until the
commit completes.

Adding an output expands workspace IDs and keeps windows on their physical outputs.
Returning outputs start empty, and merged windows do not move back. A state file from
the old fixed three-slot grid (state version 1) receives one conversion.

### Workspace modes

`config.workspaceMode` chooses how workspaces are numbered. The Workspaces tab sets it.

| Mode | Map | Numbered key `n` | Workspaces |
| --- | --- | --- | --- |
| `station` (default) | `{ outputs }`, the formula above | Shows station `n` on every output | Three stations, fixed |
| `repetitive` | `{ outputs, mode, counts, blocks }`, Omarchy's IDs: block·10 + n | Shows the output's own workspace `n` on the focused output only, as Omarchy's `o.workspaces.focus` does | `workspaceLayout.repetitive[connector]`, 1 to 10, default 5 |
| `nonrepetitive` | `{ outputs, mode, owned, counts }`, IDs 1 to 20 | Shows workspace `n` on the output that owns it | `workspaceLayout.nonrepetitive[connector]`, the numbers it owns, default five each |

The tab labels `station` as Station. Station offers stations 1 to 3; others appear while
they hold a window or are shown. With two outputs the first shows 1, 3 and 5.

Repetitive counts belong to each connector, so every monitor keeps its own.

Non-repetitive `owned[i]` lists the numbers output i owns. The lists hold 1 to 10 numbers
each and together exactly 1 to their total, at most 20; numbers past the total belong to
the last output. The saved lists apply only when they cover exactly the outputs present
and fit together. Otherwise each output gets five consecutive numbers in role order, so
two outputs own 1–5 and 6–10. A Non-repetitive map saved before `owned` reads as
consecutive blocks from its counts.

Repetitive takes each output's block from Omarchy's
`~/.local/state/omarchy/monitor-workspaces` (block, connector, identity per line), which
Omarchy's indicator reads too. An output the file does not list gets the lowest block no
line holds, internal panels first, as Omarchy assigns it. A changed file re-plans the map.
A Repetitive map saved without `blocks` still decodes with Station's IDs and migrates into
the blocks.

The numbered keys reach 1 to 10. Non-repetitive workspaces 11 to 20 are reached with
arrow navigation and the bar.

On a fresh install, when neither `config.json` nor `state.json` exists, Station reads
`hyprctl workspacerules -j` before its first start, while every rule is still the user's
own, and keeps the assignment it finds (`Grid.adopt`). Only numbered rules naming a
present connector count, and a later rule for a number wins. Rules that give each monitor
slots 1 to k of its own block of ten select Repetitive with k workspaces there; rules
that split one range select Non-repetitive with those numbers, a missing number joining
the monitor of the number below it and a monitor with no rule taking the next five. With
no such rules, one monitor, or an assignment the modes cannot hold (more than ten on a
monitor or numbers past twenty), the defaults stay. The user's rules stay in their
configuration, and Station does not read them again.

With one output the modes number the same workspaces, so the tab disables the mode
selector and says it works only on multiple monitors. The saved mode stays in effect.

A Station map has no `mode` field, so maps saved before the modes existed stay valid.
Applying a mode or layout that changes the map runs the journaled migration below. Only
`idle` accepts such a change; bar options apply in any state. Within the same kind a window
keeps its number: Station and Repetitive keep the station and output, so switching
between them moves nothing, and Non-repetitive keeps the workspace number and moves it to
its new owner, including after a drag. Across kinds a window keeps its output and its rank in that output's list,
clamped to the output's last workspace, so a Station to Non-repetitive round trip returns
it to its station. After a Non-repetitive migration each output returns to one of its own
workspaces; Repetitive outputs keep what they show.

Only Station mode switches every output together. In the other modes follow focus is off,
a moved window does not switch the other outputs, and Move across steps the window's own
number at an outer edge.

### Which stations exist

`existing = {1..3} ∪ {stations with a grid client} ∪ {stations displayed}`. Keys still
reach stations 4 to 10. Repetitive steps through the focused
output's own count, its occupied numbers and the one it shows. Non-repetitive steps
through 1 to the total, every occupied number and every shown number. The bar lists the
same numbers.

- `SUPER + n` reaches any station 1 to 10.
- Arrow navigation moves to the next or previous existing station, with no wrap. At
  the edge it does nothing.
- Window moves go to exactly `s ± 1`.

### Role swap

A swap exchanges the two outputs' preferred lanes, then runs the journaled migration.
Each window keeps its station and physical output, and its workspace ID changes. In
Mirror, the role selects the source: a swap applies the new source and sink before
migrating, so no destination is still a sink.

### More than three outputs

Station manages at most three enabled, non-mirrored outputs. A fourth is **unmanaged**.
Station excludes it from follow focus, lane lookup, window actions and reconciliation,
never touches its windows, and never disables anything by itself. The `status` IPC
reports it.

## Actions

### Direction

`config.direction` is `ltr`, `rtl`, `ttb` or `btt`. It maps a physical arrow key to a
station step on one axis and returns no step on the other axis.

### Switch

Apply rules for the map, focus each output's workspace, and finish on the previously
focused output. One eval batch does all of this.

Numbered requests during a switch keep the latest target and return `queued`. That
target runs after the batch if the map is still ready. A topology operation drops it.
Preview, migration and window moves return `busy`. A Lua error response must not update
the saved station, even if the process exits successfully.

### Send

`SUPER + SHIFT + n` sends to the same output on station n and follows.
`SUPER + SHIFT + ALT + n` sends without following. Numbered sends also accept an
unpinned active window in Omarchy's `special:scratchpad` on a managed output. Other
special, named, pinned and unmanaged windows stay excluded, and automatic migrations
never take scratchpad windows.

### Move across

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

### Starting station

A login starts on Station 1, whatever was open at shutdown. Station keeps the
`HYPRLAND_INSTANCE_SIGNATURE` it last started under in `~/.local/state/omarchy/station/session`.
A different or missing signature means a new login. The same one means a shell restart,
which keeps the station whose workspace is focused, and the saved `lastStation` when the
focused workspace is outside the map. The focused workspace alone cannot tell a login:
Hyprland's first workspaces and what the shell sees at login are not reliably Station 1.

### Workspace authority

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

### Follow focus

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

## Keybindings

| Action | Default | Replaces |
| --- | --- | --- |
| Switch to station n | `SUPER + 1…0` | Omarchy workspace switch (`SUPER + code:10…19`) |
| Move window to station n, follow | `SUPER + SHIFT + 1…0` | Omarchy move to workspace |
| Move window, no follow | `SUPER + SHIFT + ALT + 1…0` | Omarchy move silently |
| Previous or next station, LTR/RTL | `CTRL + SUPER + Left/Right` | Omarchy grouped-window focus |
| Previous or next station, TTB/BTT | `CTRL + SUPER + Up/Down` | None; personal conflicts require approval |
| Move across outputs and stations | `SUPER + SHIFT + CTRL + arrows` | Omarchy move window to monitor |
| (unbind only) | `SUPER + SHIFT + ALT + arrows` | Omarchy move workspace to monitor, which renumbers the workspace and breaks the map. A personal bind on the combo stays. |

IPC targets the service-owned handler: `omarchy-shell yakumy.station <method> <arg>`.
Its methods are `switchStation`, `sendToStation`, `sendSilent`, `goDirection`,
`shiftWindow`, `togglePanel`, `previewLayout`, `setDisplayEnabled`, `keepPreview`,
`revertPreview`, `setMode`, `setDirection`, `approveBinding` and `status`. All arguments
are validated strings. The `shell call` form reaches only loaded panels, so do not use
it.

Rules for applying binds:

- `hl.unbind` removes every entry on a combo, but only for the modifier order it was
  registered with. A replacement unbinds every order, otherwise both binds stay and both
  fire. Use it only for known Omarchy defaults in the table, combos the user approved,
  and combos in `state.appliedBinds`.
- Do not apply a combo with an unresolved conflict.
- Apply once per configuration generation. A reload clears runtime binds.

Conflict sources, in order:

1. `omarchy menu keybindings --print`. This is the identity source, because
   `hyprctl binds -j` cannot identify Lua `code:` keys.
2. `hyprctl binds -j` as a cross-check for plain keys.
3. A scan of `~/.config/hypr/bindings.lua`.

Station ignores entries whose description starts with `Station:`.

Omarchy 4.5.0 ships its own `SUPER + SHIFT + CTRL + arrow` binds ("Move window to
left/right/up/down monitor"). Station treats them as stock defaults: they are replaced
without a conflict, because Station's `shiftWindow` also crosses stations. Station keeps
its binds so older Omarchy releases still work.

> **Reminder for Station 5.0.0:** Omarchy's binding is then reliable. Remove the four
> `shift-*` definitions in `lib/keybindings/Binds.js` and the `Move window to … monitor`
> entry in `stockOwner`, and drop the Move across section if Omarchy's movement suffices.

| Status | Meaning |
| --- | --- |
| Replacement | A known default or an approved combo. Applied. |
| Conflict | Shown with its owner and a choice to pick another key or replace. Not applied. |
| Free | Source 1 succeeded and nothing matched. |
| Unverified | Source 1 failed or is empty. Applied with a badge. A fallback can add conflicts, but it never turns unknown into free. |

The Keybindings tab turns red with a count while a conflict remains. The picker uses
ordinary buttons and key events. It never uses an editable text control, because Qt's
writable inputs read the clipboard ([finding](platform-findings.md#11-known-traps-consolidated)).
Escape cancels capture. Tab leaves capture. Apply is explicit. Hiding the editor,
changing tabs, closing the panel or losing focus stops capture.

## Display edits

### Modes

- **Extend:** enabled outputs form one desktop.
- **Mirror:** enabled outputs mirror the source. The editor keeps each output's
  independent geometry from the marked block, because sinks report the source's
  coordinates.
- **Single:** the other outputs are disabled and windows merge onto the target.

Never leave zero real outputs. If the Single target disappears, fall back to Extend.
Always send explicit `disabled` and `mirror`, because `mirror = ""` is the only way to
clear a previous mirror.

### Geometry

The canvas uses Hyprland logical coordinates: `w = pixelW / scale`, with width and
height swapped for transforms 1, 3, 5 and 7. Edges snap to neighbors and to a 10-unit
grid. Parallel alignment snaps only within 20 logical units, so unequal monitors can
stay attached at any offset. When rotation, scale or resolution changes a rectangle,
keep its strongest shared edge and reposition it without overlap. Overlapping layouts
cannot be kept.

### Marked block

The block sits at the **beginning** of `monitors.lua`, so later personal rules win.

- Generated blocks use a bounded DRM presence check at config evaluation (cards 0 to
  15, validated connectors, 32-byte reads). `hl.get_monitors()` can be empty at cold
  login.
- Failure, a missing function or an empty list must never disable an output or break
  evaluation. Each layout has an exclusive fallback that applies its saved geometry
  with outputs enabled and unmirrored.
- On a warm reload, only the combined final-state rules run. A geometry prepass would
  briefly enable a disabled output.
- The service never enforces the mode afterward.
- `mode` must be an exact element of that monitor's `availableModes`.

An older block at the end of the file migrates once, with a backup and a source
comparison. That upgrade applies the current Lua, which clears old runtime appearance
rules.

### Preview

Topology edits use a preview, a **detached 20-second watchdog** and a **12-second**
Keep/Revert countdown. The countdown is visible on every tab, because running out can
turn a monitor off.

1. Write `preview.token` and start the watchdog from a fixed template. The arm step
   touches the token before every apply. A watchdog stands down if the token is newer
   than its window, so a long session is not rolled back by its first watchdog.
2. If the change endangers an output with an open panel, evacuate first (see
   [Evacuation](#evacuation)).
3. Enable a disabled destination, focus the survivor, then apply the remaining rules.
4. Migrate windows to the temporary map. The journal keeps the original baseline.
5. Renew the token and show the full countdown.

The draft stays editable during a preview: drag, rotate, mode and enable join the same
session. `previewBefore` and the baseline are captured once, so Revert returns to the
start of the session. New windows keep their station through recovery. Role swaps and
side controls work only from `idle`. Mirror source changes use the guarded preview.

Revert or timeout restores the runtime state and the baseline. An external reload,
unexpected hotplug or external geometry change cancels the preview and adopts the
result. It does not replay the old target.

At startup, a stale token means a crashed preview: remove it and reload. A baseline in
the journal also restores window ownership, even if the watchdog already consumed the
token. Clear the baseline only after Keep or completed recovery. The watchdog reloads
current configuration, never a cached copy.

### Evacuation

**Never disable or mirror an output that owns an open keyboard-focused panel.** Its
layer surface holds a focus grab, and destroying it during monitor removal can crash
Hyprland.

A panel on another output stays open. `KeyboardPanel` also keeps a non-focused dismiss
surface on every other output, so a leaving output sheds that one first. No hand-off
runs when no output leaves and the panel stays put.

1. Publish the request fields, then assign the serial last. `panelEvacuationReleases`
   names the leaving outputs when the panel's own output survives.
2. **The panel's output survives:** the widget hides the dismiss surfaces on those
   outputs and stays open. **It leaves, or the host's surfaces cannot be found:** the
   widget closes. Either way it waits 180 ms for unmap, then acknowledges with the serial
   and output.
3. Enable and focus the survivor, then apply destructive rules.
4. A closed panel reopens on the survivor only after compositor success. A panel that
   stayed open takes keyboard focus again when the transaction ends, and shows the
   dismiss surface again on any output that did not leave.

A missing acknowledgment after 2.5 s aborts. No rule is dispatched. A mode action on
the proxy probes the bridge every 30 ms during this window, so the request is not left
waiting for the general panel poll.

### Keep

Keep is a transaction:

1. Capture the accepted options before writing candidates.
2. Wait for both candidate save acknowledgments, not a fixed delay.
3. Compare the source with the text read before.
4. Back up as `monitors.lua.bak.<timestamp>`, keeping the last 5.
5. Replace the file atomically. Refuse symlinks, and change only the marked block.
6. Let Hyprland's file watcher apply it, then check `hyprctl configerrors`.

Events during Keep must not reset the draft or apply the previous mode. On success,
commit the options and take a fresh snapshot before reconciling. On failure, restore
only if the file still matches Station's candidate, then reload. Newer external edits
survive. External editors share no lock with Station, so this is optimistic detection.

Scale (1, 1.25, 1.6, 2, 3, 4), Resolution and Refresh use the same file transaction
directly from `idle`, with no preview, watchdog or countdown. Their selections keep an
exact mode string.

### Internal monitor Off flag

Omarchy's `internal-monitor-disable.lua` is a shared control. Station observes it and
does not change it during observation, Revert, timeout or side-control saves, or during
a preview that leaves an external output enabled.

When the user turns that output on and presses **Keep**, Station clears only the exact
recognized flag in a checked two-file transaction: compare both sources, suspend
autoreload, back up with a non-`.lua` suffix, remove the flag, save, reload once, and
restore autoreload on every exit. Failure restores only files that newer edits have not
replaced. Modified or unrecognized toggle Lua is preserved. A successful Keep deletes its
flag backup.

A preview that leaves **no external output enabled** cannot leave the flag in place.
Omarchy's `omarchy-hyprland-monitor-internal recover` runs on every monitor event,
deletes the flag as soon as no external output is active, and reloads, which replaces
the preview with the saved layout. For that case only, Station parks the exact flag in
its state directory before any output changes, with autoreload suspended, because
removing a loaded file triggers a watched reload.

| Outcome | Parked flag |
| --- | --- |
| Keep, the internal output is on | Deleted |
| Keep, the internal output is off | Returned |
| Revert, timeout, cancelled preview, failed Keep | Returned before the reload |
| Watchdog, or a restart that finds a preview token | Returned before the reload |

A parked flag never replaces a flag written since.

### Enabling outputs

`hl.monitor` returns before a re-enabled output exists, so a focus sent straight after it
can answer `monitor not found`. Station retries that exact answer for up to 2 seconds,
only for an output it just enabled. Any other answer fails the preview.

Single reads back from the compositor as every other output disabled. Leaving Single
for Extend or Mirror therefore turns on **every** connected output. An output that was
switched off with its card before Single comes back on, and the user can turn it off
again.

### Screen recovery

After Keep or Revert settles, Station compares enabled non-mirrored Hyprland outputs
with Quickshell's screen list. A missing screen means the host lost its surfaces. If
another active output remains visible, Station cycles the missing output once and
restores its validated rule. It never cycles the only visible output.

## Windows tab

The Windows layout preview omits bar indicators and reserves no space for them.
Simulated windows fill each monitor inside the chosen outer gap on all four edges.
This preview does not change the compositor's actual bar-aware work area.

The controls change **global compositor settings**: inner gap, outer gap, Dwindle split,
rounding and animation speed.

| Control | Range | Notes |
| --- | --- | --- |
| Inner gap | 0 to 160 | The full visible gap. Hyprland's `gaps_in` is half of it. |
| Outer gap | 0 to 160 | Never moves the bar. Solid and Blur default bars keep it beside the bar. A Transparent default bar gets no gap on its edge. A Pill bar ignores it: windows sit `Style.space(8)` from the pill in every background, the same safe space the pill keeps from the monitor. |
| Next-window split | 25 to 75% | Dwindle only |
| Rounding | 0 to 20 | Follows `decoration:rounding`, which Omarchy also uses for shell corners |
| Animation speed | 0, 0.25, 0.5, 0.75, 1, 1.24, 1.5, 1.75, 2 | 0 disables animations. Window duration is 400 ms divided by speed. |

Sliders preview while dragging and apply on release:

1. Suspend autoreload.
2. Save only that control's entry in the marked section at the beginning of
   `looknfeel.lua`.
3. Compile the candidate for syntax, without executing personal Lua.
4. Apply only that setting through `hyprctl eval`.
5. Restore autoreload on every exit, then read back the applied value.

The bar edge is handled by runtime `hl.workspace_rule` entries named `m[<connector>]`
with a directional `gaps_out` table, written by `BarLayerSync.syncBarGaps` (policy in
`Windows.gaps`). They are never saved. Station sends them after a reload, a bar
setting change, a display change and a read-back of the outer gap. A monitor that
once had a rule keeps getting one, so leaving Transparent restores the full gap.

Success causes **no full reload and no fixed sleep**. A failed apply conditionally
restores the file and reloads. Personal settings later in Lua order win on the next
reload, and Station shows that result without retrying.

The slider keeps its selection during input and through read-back. Unrelated updates
must not reset an active edit. Controls stay busy until read-back ends, including a
failed read. Proxy actions refresh the busy snapshot before the host slider completes
release.

The panel shows global defaults. It does not inspect per-window rules. External values
display unrounded until the user edits that control.

The preview shows two windows per monitor at real proportions, with names outside the
rectangles. After a speed change, WINDOW tiles move through every enabled monitor
in order, one transfer at a time, while NEXT WINDOW tiles stay and reflow. With one
enabled monitor, the two tiles exchange sides, pause, then exchange again so WINDOW
finishes on the left and NEXT WINDOW on the right. Disabled monitors stay still.
Repeated changes queue the latest speed without interrupting a move. This never
moves a real window.

## Color Match

Color Match makes monitors agree on white. Each adjusted monitor gets one ICC v4
display profile, and Hyprland applies it through its own color pipeline (it builds a
3D LUT with lcms2). Nothing else is installed.

| Control | Range | Default | What changes in the profile |
| --- | --- | --- | --- |
| Temperature | 4000 to 9000 K, steps of 100 | 6500 K | Per-channel gains along the Planckian locus, relative to 6500 K |
| Tint | −100 (green) to +100 (magenta) | 0 | Up to 30% less green, or less red and blue |
| Brightness | 50 to 100% | 100% | All three gains. It can only dim. The track runs on to 150% so 100% sits in the middle; past 100% the knob returns and the row says 100% is the maximum. |
| Gamma | 0.60 to 1.40 | 1.00 | The shared tone curve: the sRGB curve raised to 1/gamma. Higher darkens midtones. |
| Saturation | 0 to 200% | 100% | A Rec. 709 luminance-preserving saturation matrix. 0% is black and white. |

- Gains are normalized so the brightest channel is 1 before Brightness, so no channel
  clips. The gains and saturation go into the colorants (`rXYZ`, `gXYZ`, `bXYZ`) as
  `sRGB × (gains × saturation)⁻¹`. lcms inverts that description, so the screen receives
  the corrected signal. Every slider puts its default in the middle of its track.
  Saturation 0 has no inverse, so the matrix uses 0.2% instead;
  lcms then sends every color as grey within one code value. All channels share one
  tone curve, because Hyprland cannot represent split curves. The profile has no `vcgt` tag: see
  [Platform findings](platform-findings.md#color-match-icc-profiles-2026-11-11).
- Settings are stored in `config.colorMatch` by display identity, so they follow a
  monitor to another connector. A monitor at all defaults has no entry and no profile.
- An HDR monitor (`cm` `hdr` or `hdredid`) gets no profile, because an ICC replaces
  its HDR preset. The tab disables the controls for it and says why.
- Station owns `toggles/hypr/station-color.lua`, which Omarchy loads after
  `monitors.lua`. It calls `hl.monitor({ output, icc })` with only those two fields,
  which keeps the monitor's mode and position. Each call checks that the profile file
  exists and runs under `pcall`, so a missing profile never becomes a config error.
- Profiles are named `<connector>-<hash>.icc` from their bytes, so Hyprland never
  reuses a stale file. Unused profiles are deleted after a successful apply.

A slider applies on release through the fixed `Transactions.colorMatch` script:

1. Write the new profiles, then compare the toggle file with the version the owner read.
2. Suspend autoreload, replace the file atomically, and apply.
3. A changed or new profile applies live with `hyprctl eval` of the changed monitors'
   rules: no reload. A connected monitor that loses its profile (Reset, or all defaults)
   needs one `hyprctl reload`, because Hyprland cannot clear an ICC live (`icc = ""` is
   rejected).
4. Restore autoreload on every exit. A failed apply restores the file only if it is
   still ours and reloads. The owner then restores the previous settings and saves
   nothing.

The tab shows the dragged value live and applies on release. Controls stay disabled
while an apply runs, and an edit is refused as busy unless Station is idle, because a
reset's reload would cancel a display preview or migration. Startup, reload and hotplug reconcile the file with the saved
settings, and a matching file costs nothing. A disconnected connector keeps its row,
so unplugging never forces a reload. Removal deletes the file before its reload.

## Bars

`Bar.qml` hosts one Omarchy-derived bar per connected output. Activating it removes
Station's persisted widget row atomically and injects a virtual Station slot. Plugin
disable therefore removes the last enable reference and unloads the service. Never edit
packaged Omarchy files for per-monitor behavior.

Station preserves the host's six layout sections: `left`, `centerBegin`, `center`,
`centerEnd`, `right`, and `tray`. The flanking center sections grow away from the
center box without moving its anchor, horizontally or vertically. Their extents
count toward Pill backgrounds, minimum width, and maximum content size. Older
three-section layouts continue to work. Widgets in `tray` render inside a tray
widget that provides a `sectionHost`; older tray widgets without that port keep
their previous behavior.

Inline settings updates and widget placement lookup cover every section. Dragging
to the outer edges of the center box inserts into the corresponding flanking
section. The tray drawer accepts widgets and cannot contain its own hosting tray.
One full-bar IPC handler refreshes the hidden-state probe on every monitor.

| Control | Rule |
| --- | --- |
| Presence | At least one enabled output keeps a bar. A disabled output's remembered bar does not count. |
| Position | Four side arrows per monitor. Omarchy's Bar → Position menu and bar dragging change only their own monitor. Other monitors keep their edges. |
| Content size | From `Style.font.body` to the live maximum. Above the default, each module zooms uniformly. |
| Height | From the theme's thickness to 5% of the mode's shorter native side. A live minimum can clamp it. |
| Width | 1 to 100%. Requests below the measured non-overlap minimum stay visible and the bar clamps. |
| Enabled | The switch moves at once, and `BarLayout` applies the change after the throw, because building a bar blocks the shell's thread. While the panel is open the host write is deferred like every other bar control, because it would rebuild all widgets and the panel with them. Closing the panel in that gap still applies it. A refused change moves the switch back. |
| Background | Solid, Transparent or Blur. See [below](#bar-background-blur). |
| Style | Omarchy default, or Pill with separate left, center and right islands. |

### Bar background blur

A layer rule draws nothing while `decoration:blur:enabled` is false, which is Omarchy's
default. While at least one enabled bar is set to Blur:

- Station enables its `station-bar-blur` layer rule.
- If global blur is off, Station turns it on at runtime with 3 passes, records the passes
  it found, and enables a `no_blur` window rule, so windows look as they did.
- If global blur is already on, Station changes nothing else. Those settings are the user's.

When no bar wants Blur, Station disables the layer rule and returns what it changed. A
reload clears the override, and the next sync applies it again. Nothing is written to a
file or to `state.json`.

- The Omarchy default bar begins at the physical monitor edge. A Pill bar keeps a safe
  space of `Style.space(8)` from that edge and from the ends of its span. Auto exclusion
  reserves the configured thickness plus that space. Window gaps never move the bar.
- A side change reflows in place, so an open panel survives. While the panel is open,
  `config.bars` is authoritative and the shell config write waits for close.
- The panel follows the current bar edge and configured thickness. The host positions
  it using logical thickness, independent of transient layer-window dimensions.
- Drag empty bar space to move the bar, or hold a widget for 200 ms before dragging.
  A short widget drag still reorders widgets; releasing a held move does not click it.
- Partial-length bars sit centered in a full-length, input-masked surface, because
  Omarchy's keyboard panels need the surface to match the screen.
- Content zoom scales the subtree, re-rasterizes text and decodes images at the matched
  physical size.

### Open apps

The Workspaces tab sets `compactMode` and `showOpenApps`, and the indicator style as
`indicatorStyle`: `prefixed` (S1, or W1 outside Station mode), `number` or `roman`.
A saved `dots` style, which did not fit the compact modes, loads as `prefixed`. `compactMode` is Off (`off`), On hover (`hover`, the default) or On (`on`).
`showOpenApps` (default on) adds app icons in Off and On hover; On shows none. The old
`stationAppsMode` loads as Always on → Off, On hover → On hover, Off → On without apps.

In Station mode every bar shows the station. In Repetitive and Non-repetitive each bar
shows its own output: its own numbers, the one it shows and the apps on them, and a
click shows that number on that output. It reads the shown workspace from Quickshell's
monitor and refreshes it on workspace events, because Omarchy's indicator, which would
otherwise refresh it, is usually hidden.

- Off lists every available number with no chevron. Omarchy's tiling square glyph
  (U+F14FB), drawn by `WidgetButton` at Omarchy's icon size, stands for the current one,
  as in Omarchy's indicator.
- As in Omarchy's indicator, a number that is not shown and has no window is drawn at
  half opacity, so the current one reads as active.
- On hover shows the current number and a chevron, and reveals the rest, with one icon
  per mapped window when apps are on. It uses the stock tray's 600 ms OutCubic motion,
  and the current label stays opaque.
- On shows only the current number, and its compositor feed stops.
- Clipped labels and icons accept no clicks until fully open, so the logo always opens
  the panel.
- Labels and icons switch the whole station. Scratchpads are excluded. A pinned window
  appears once at its home station.
- The feed uses the saved map, and a pending journal's identities take precedence.
- Icons keep original colors and full opacity, regardless of focus.

## Wallpaper

Wallpaper is independent of workspace and monitor policy and emits no monitor commands.
Its modes are Same on all (the default, following Omarchy), Per monitor, and Span.
The five control rows are Mode (dropdown), Follow Omarchy theme (Yes/No dropdown),
Choose image, Choose theme background and Choose theme. The three buttons fill their
row's padded width, with the selected image filename, current background filename,
and current theme name beneath them. Per monitor shows `Selected: <connector>` above
the controls; the layout selects that monitor. Other modes leave that heading empty.
The theme buttons close Station and open Omarchy's native Background and Theme
menus. There is no Use Omarchy wallpaper or Reset frame button; framing remains
available through canvas gestures.

- Outputs come from observed Hyprland state. A returning output recovers its choice.
  Mirror sinks inherit through the compositor.
- Span preserves logical positions, gaps, rotations and relative sizes. The monitor
  group moves over a fixed image, zoom runs from 1 to 8, and pan stays inside the
  image. The recommended resolution is logical bounds × maximum scale × zoom. It is a
  recommendation, never a limit.
- Same on all and Per monitor frame each monitor separately. Dragging inside a monitor
  moves the image with the pointer, the scroll wheel zooms around the pointer, and with
  the canvas focused the arrow keys and `+`/`-` act on the selected monitor. Zoom runs
  from 1, the largest crop that still fills the monitor, to 8, so a frame never shows an
  empty edge. Frames are per monitor identity and per mode, are saved in the profile
  under `frames`, and take effect on Apply. A profile without `frames` loads with every
  monitor centered at zoom 1. A centered, unzoomed frame is not stored, so a monitor
  with no frame under Follow in Same on all stays on the stock surface. Choosing an
  image drops the frames made for the image it replaces.
- A canvas gesture draws from a local frame and reaches the controller when it settles,
  because the panel reads the draft through a polled bridge. The local frame ends when
  the draft answers, or after 1 second if the controller ignored it.
- Follow mode uses the live background and a profile keyed by theme and background
  path, keeping the newest 64. An `inotifywait` process watches Omarchy's
  `~/.local/state/omarchy/current` directory and the image's directory, and Station
  reads the theme once for each settled change. An image replaced in place also
  refreshes. If the watch ends unexpectedly, Station reads once and retries every
  5 seconds.
- With Follow off, a pinned profile ignores theme changes. Apply makes the snapshot,
  because a theme may rewrite the same path.
- Choosing an image closes the panel first, because the native chooser needs focus.
  The panel returns to Wallpaper on success, cancellation and error. Accepting a
  safely prepared local image turns Follow off; cancellation leaves Follow unchanged.
- The service draws click-through bottom-layer surfaces above the stock background. The
  default mode leaves the stock surface visible.
- Animated images show a static first frame.
- Under Follow, a matching theme intro uses the saved wallpaper crop on every output,
  including Span pan/zoom and per-monitor frames. Station keeps its still visible until
  OWE confirms that the crop has been presented on every output. The same normalized
  rectangles apply to the video and its fade into the final still; Station then resumes
  its saved image framing. The renderer holds the cropped opening frame until Station
  reveals it and releases playback, so the framing handshake does not skip the opening.
  The hold expires after two seconds if the covering client disappears. Playback
  remains one OWE decoder, never one player per screen.
- Framed intros require OWE's `source-rects` renderer API and `intro_path` status field.
  Older engines keep Station's still visible. Requests are scoped to the renderer's
  media generation; stale replies, missing images, unavailable outputs and engine errors
  cannot reveal an unframed video. Observation is bounded to a theme-change window and
  ends after a completed intro. Pinned wallpapers do not follow intros.
- For engines advertising `composition_handoff`, Station keeps its transparent layer
  mapped throughout playback, restores only its cropped image at the end, and waits
  for two render frames before acknowledging. OWE enables the stock background only
  after that acknowledgment. This avoids both a polling gap and the compositor's
  layer fade exposing the unframed wallpaper.

### Image safety

A selected path never reaches a QML `Image`. `SanitizeWallpaper.pl` runs with fixed
argv, recognizes PNG, JPEG, GIF, BMP and WebP by magic bytes, and writes a private copy.

- Limits: 128 MiB input, and for PNG 4,096 chunks and a 256 MiB decoded raster.
- PNG keeps only IHDR, PLTE, IDAT, IEND and small rendering chunks. It discards text,
  ICC, EXIF, animation and unknown chunks without decompressing them.
- Private image copies retain the source basename with the detected format extension,
  including across Apply snapshots, so the Choose image hint stays recognizable.
- Only marked paths under Station's wallpaper directory render. Older unmarked choices
  stay hidden until restaged and the save is acknowledged.
- A save failure restores the previous wallpaper. Copies survive mode changes, failed
  saves, disable and removal, and Station evicts no cache.

## Panel

The panel is a bar-widget popout. The Displays-style popout replaces the on-demand panel
kind, which does not inject the `anchorItem` and `bar` that `KeyboardPanel` requires.

- The frame requests `Style.space(996)` by `Style.space(620)`, capped by the host. Tabs
  do not change it. The header and tabs stay fixed, and the body scrolls vertically only
  on overflow, returning to the top on a tab change.
- Displays keeps its Mode menu inside the layout canvas at the top right. It uses
  the same preview and panel-evacuation path as the former toolbar menu.
- The tabs are Displays, Workspaces, Bar, Windows, Color Match, Wallpaper, Keybindings and Settings. Service
  setters keep numeric tab indices, and `Tabs.js` names them for feature code.
- Position is Left (at the bar icon, the default) or Center on the current monitor. It
  uses the output's full-screen card and stays clear of the bar on small screens.
- Settings holds the two Show switches, follow focus, panel position,
  and the installed version. Compact mode and open apps are on the Workspaces tab.
- The Workspaces tab's monitor positions are fixed: no monitor drag and no selection,
  only zoom and pan. Each managed output shows its name, its role and its workspaces in
  the top-left corner.
- Every Workspaces control edits a draft that the layout draws at once. Cancel and Apply
  appear once the draft differs from the saved values. Apply sends the whole draft in one
  `setSetting("workspaces", …)` call; Cancel restores the saved values.
- In Repetitive every monitor has − and + after its badges (1 to 10). In Non-repetitive
  only the last monitor has them: + adds the next number to it, − removes the highest
  number, wherever it is, while its monitor keeps one. Non-repetitive badges drag onto
  another monitor, which then owns that number; each monitor keeps 1 to 10.
- The Workspaces frame has five equal-height dropdown rows: Mode, Indicator style,
  Compact mode, Stations Direction and Show open apps. Titles sit at the top left,
  dropdowns fill the width within the row padding, and hints sit at the bottom left.
  Mode defaults to Station; Compact mode defaults to On hover. Direction moves from
  Displays to this draft and retains LTR, RTL, TTB and BTT. It is disabled outside
  Station mode with "only work with Station mode". Show open apps offers Off and On
  and is disabled with Compact mode On, retaining its saved preference.
  Mode retains the single-output restriction and the Non-repetitive drag hint.
- Text size offers 9, 10, 11, 12, 13, 14, 16 and 20px. It runs
  `omarchy-display-text-size` and changes shell, GTK and terminal text globally.
  The per-monitor control is Scale.
- Brightness reads and writes carry the selected connector, and a notice belongs to its
  control.

### Surviving a rebuild

A bar rebuild destroys the widget and its popout. The service keeps the intent:

- `panelWanted` is written on every open change, and destruction never writes it. A
  rebuilt widget reads `true` and reopens. A real close writes `false`.
- A shell restart starts closed, because the flag is in memory.
- A change that lands before the service binding resolves is held and replayed.
- `closeForPopoutSwitch` is not a dismissal. The bar closes the old copy after the new
  copy opens. The decision waits one event-loop turn, then keeps the flag if any live
  copy shows the panel.
- `rememberedTab` and `rememberedDisplayName` come back too. A real close clears the tab.

## Stock widgets

`state.stockLease` and `state.displayLease` have the shape
`{ wasEnabled, section, index, disabledByStation }`.

- Settings' Show Omarchy default workspace indicator is `hideNative` inverted, in every
  mode. It shows or hides Omarchy's own installed indicator next to Station's widget;
  Station draws no workspace numbers of its own. Omarchy's indicator numbers each
  monitor in blocks of ten, so it matches Repetitive; in Sync and Non-repetitive it
  shows Omarchy's numbering, not Station's.
- Settings' Show Omarchy Display Icon is `hideDisplay` inverted and defaults to Off.
- The grace-delay control is removed. New configurations use no delay; an existing
  saved `graceMs` remains honored.
- With Show off (the default for both widgets; a saved `hideDisplay: false` stays),
  Station records placement and disables an enabled widget. It records a disabled widget
  as such, and startup and removal never enable that one.
- Restoring happens only for `disabledByStation && wasEnabled`.
- An explicit Show also enables a widget hidden before Station acquired it.
- The workspace widget returns behind Station with `omarchy bar move --after`, falling
  back to its recorded place. `bar put` leaves a present widget where it is, so use
  `bar move`.
- Bar writes rebuild the bar, so Station runs them one at a time.
- Leases retain section and index in all six host sections. Removal validates and
  restores these placements with the same fixed-script argument checks.

## Removal and restart

`Component.onDestruction` fires on disable, removal and shell restart alike. It starts a
detached fixed script with validated positional arguments:

1. Wait, then look for the shell for up to about 15 s.
2. If the shell answers and `listPlugins` shows Station enabled, stop. This is a restart.
3. Otherwise restore only the leased widgets.
4. Neutralize the current marked block by changing `disabled = true` to `false` and
   clearing `mirror`, with a backup and an atomic replace. Geometry stays. Single and
   Mirror do not outlive the plugin.
5. Delete Station's `station-workspaces.lua` and `station-color.lua` toggle files.
6. Run `hyprctl reload`, which clears runtime binds and rules and returns every output
   to its own colors. `SUPER + n` must work immediately.

If the shell never answers, the script does nothing, and the user runs `hyprctl reload`.
Preferences, state, backups and wallpaper copies remain.

## Security

- Use argv arrays or fixed scripts with validated positional arguments. Never interpolate
  device text into shell or Lua.
- **Connector:** must match `^[A-Za-z0-9_.:-]{1,64}$`, then may reach Lua (escaped) or argv.
- **EDID-derived fields** (`description`, `make`, `model`, `serial`) are untrusted: use
  them for matching and display only.
- Modes must match the monitor's allowlisted `availableModes` exactly.
- The bridge exposes detached data and a closed action list, never a QObject. The
  replacement-bar API exposes no generic command.
- Atomic file writes refuse symlinks and change only marked sections.
- Logs contain no command lines with unvalidated input.

## Performance targets

Press-to-switch has a target of p50 under 120 ms and p95 under 180 ms. [LIVE] Twenty
physical key samples measured p50 66 ms and p95 68 ms during the platform gate.
