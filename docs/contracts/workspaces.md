<!-- summary: Workspace IDs, the saved map, migrations and their journal, Station/Repetitive/Non-repetitive modes, how many stations exist, more than four outputs. -->
<!-- code: lib/stations/Grid.js lib/stations/Workspace* lib/platform/Store.js lib/stations/*Tab.qml lib/stations/*Layout.qml -->
# Workspace numbering

For the ordered active outputs and `N = outputs.length`:

```text
workspace(station, output) = (station - 1) * N + index(output) + 1
stationOf(id, map)         = floor((id - 1) / map.outputs.length) + 1
```

There are ten stations and one to three active outputs. Single and Mirror have one
station-bearing output. Numbering has no holes: with two outputs, S1 is workspaces 1
and 2, and S2 is 3 and 4. Non-grid, named, special, pinned and unmanaged windows are
excluded from migration.

## Active map

- Extend uses the enabled managed outputs.
- Single uses its target, or a surviving fallback.
- Mirror uses its source.
- New outputs join Extend. Explicit Single keeps them out.
- A zero-output interval preserves the saved map.
- A station's meaning never changes retroactively: always decode existing IDs with the
  saved map, never with current hardware.

## Migration

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

## Workspace modes

`config.workspaceMode` chooses how workspaces are numbered. The Workspaces tab sets it.

| Mode | Map | Numbered key `n` | Workspaces |
| --- | --- | --- | --- |
| `station` (default) | `{ outputs }`, the formula above | Shows station `n` on every output | `config.stationCount`, 1 to 10, default 3; more appear while they hold a window |
| `repetitive` | `{ outputs, mode, counts, blocks }`, Omarchy's IDs: block·10 + n | Shows the output's own workspace `n` on the focused output only, as Omarchy's `o.workspaces.focus` does | `workspaceLayout.repetitive[connector]`, 1 to 10, default `stationCount` |
| `nonrepetitive` | `{ outputs, mode, owned, counts }`, IDs 1 to 20 | Shows workspace `n` on the output that owns it | `workspaceLayout.nonrepetitive[connector]`, the numbers it owns, default `stationCount` each |

The tab labels `station` as Station. `config.stationCount`, 1 to 10 with default 3, is
the number of indicators the bar lists in every mode. In Station mode others appear
while they hold a window or are shown; with two outputs the first shows the odd numbers
1, 3 and 5. In the per-monitor modes it is the starting count for a connector that has
no saved count of its own. This is a behavior change: that starting count used to be
five, and a connector with a saved count still keeps it.

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

## Which stations exist

`existing = {1..stationCount} ∪ {stations with a grid client} ∪ {stations displayed}`.
Keys still
reach stations 4 to 10. Repetitive steps through the focused
output's own count, its occupied numbers and the one it shows. Non-repetitive steps
through 1 to the total, every occupied number and every shown number. The bar lists the
same numbers.

- `SUPER + n` reaches any station 1 to 10.
- Arrow navigation moves to the next or previous existing station, with no wrap. At
  the edge it does nothing.
- Window moves go to exactly `s ± 1`.

## Role swap

A swap exchanges the two outputs' preferred lanes, then runs the journaled migration.
Each window keeps its station and physical output, and its workspace ID changes. In
Mirror, the role selects the source: a swap applies the new source and sink before
migrating, so no destination is still a sink.

## More than four outputs

Station manages at most four enabled, non-mirrored outputs. `Model.MAX_MONITORS`,
`Grid.MAX_OUTPUTS` and `MonitorsLua.MAX_LANE` hold the limit and must agree. With four
outputs, Sync writes workspace rules 1 to 40, Repetitive uses Omarchy blocks 0 to 3, and
Non-repetitive starts at `stationCount` workspaces each, clamped so the total stays
within its 20-workspace limit. A fifth output is **unmanaged**.
Station excludes it from follow focus, lane lookup, window actions and reconciliation,
never touches its windows, and never disables anything by itself. The `status` IPC
reports it.
