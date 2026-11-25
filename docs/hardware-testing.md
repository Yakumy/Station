<!-- summary: Prepare, capture, cases to run, restore, operator results. Asks the user first. -->
<!-- code: test/live/** -->
# Qualify a change on real hardware

Use this procedure when a change touches displays, migrations, evacuation or removal.

## Prepare

1. Get explicit permission for the specific cases. Crash, removal and physical unplug
   cases each need their own permission.
2. Make sure an operator can recover through a TTY. Use disposable test windows.
3. Record the source and installed revisions, the stack versions, and the connector
   names, modes, scales and rotations.
4. Back up `monitors.lua`, `looknfeel.lua`, Station's files, the Omarchy shell config
   and the internal-monitor toggle. Record hashes, `misc:disable_autoreload` and
   `hyprctl configerrors`. Keep EDID text and window titles out of public results.
5. Open identifiable windows on stations 1, 2 and 4 of each output, plus one floating
   window. Record each address, PID, class, station and output from the initial map.

## Capture

Capture these before the action, after it settles, and after you restore the setup.
"Settled" means that the operation and journal commit finished. A fixed sleep is not
a substitute.

```sh
hyprctl monitors all -j
hyprctl clients -j
hyprctl workspaces -j
hyprctl activewindow -j
hyprctl configerrors
hyprctl getoption misc:disable_autoreload -j
omarchy-shell yakumy.station status
```

## Cases

Run each mode case in both output directions and on both panel paths. Record pass,
fail or not run. Missing hardware means not run, never an inferred pass.

| ID | Steps | Pass condition |
| --- | --- | --- |
| H1 | In Extend, change the arrangement. Keep it. Repeat with Revert, then with the timeout. | Keep persists only the marked block and survives reload. Revert and timeout restore the topology and each window's station and output. Personal Lua is intact. |
| H2 | Open the panel on B. Choose Single A and Keep. Return to Extend. Repeat in the other direction, then with Revert and timeout. | A real output remains at every step. Windows keep their stations. Revert restores original outputs. |
| H3 | Mirror with A as source, Keep, return to Extend. Repeat with B. Swap the source, then go from Mirror to Single with the panel on the endangered output. | Only the source owns a station column. `mirror = ""` clears the mirror on return. Destinations match the plan. |
| H4 | Try to disable every output. Change scale, resolution and refresh one at a time. | The last real output stays on. Side controls save directly with no countdown. Exact modes apply. |
| H5 | Repeat H2 and H3, and record the serial, acknowledgment and focus order. Repeat with the panel on the survivor. | The acknowledgment follows unmap. Survivor focus precedes destructive rules. One panel reopens on the survivor. No crash. |
| H6 | Unplug B past the grace delay and reconnect it. Separately, reconnect inside the grace delay. | Stations survive. A returning output does not pull merged windows back. A fast reconnect cancels compaction. |
| H7 | During a preview, edit twice and add a window, then Revert. Repeat with an unplug and with an external reload. | The baseline survives re-edits. External changes cancel the preview and adopt the result. No window is lost. |
| H8 | With Omarchy's internal Off flag set, turn the output on. Revert, then time out, then Keep. Reload. | Only On + Keep clears the exact flag. Autoreload returns to its old value. Config errors stay empty. |
| H9 | With separate permission, kill the shell process during a preview. | The watchdog reloads current configuration. The new service resumes the journal with no duplicate binds. |
| H10 | Restart the shell once. With separate permission, disable the plugin, then remove and reinstall it. | A restart causes no cleanup and opens no panel. Removal restores only leased widgets, neutralizes rules and keeps preferences. Real number keys work. |
| H11 | With hardware, repeat H1 to H7 on four outputs and attach a fifth. Test dock, lid, suspend and cold login separately. A Hyprland headless output (`hyprctl output create headless`) stands in for a missing monitor; remove it afterward. | Four outputs keep station identity. The fifth stays untouched. Record actual behavior. |

Compute each expected destination from the committed map:
`(recordedStation - 1) * outputCount + outputIndex + 1`. Exclude pinned, special and
unmanaged windows.

Test rejected applies, source conflicts and stale acknowledgments in isolation first.
Do not corrupt real Lua or force zero outputs to create a failure.

## Restore

After each case, restore outputs, station, bar host, widgets, the toggle and autoreload.
Restore file bytes only where the current files are still this run's candidates.
Otherwise keep the newer edits and report the conflict. Never restore a stale journal
over live windows. If recovery fails, stop and preserve the evidence.

## Operator results

On 2026-11-05 the maintainer reported these working on the two-monitor setup. Each is an
operator report without captured evidence:

- The display, key and panel checks requested after the refactor.
- Closing the lid.
- Logging out and back in.
- `omarchy theme set`, with Station following the change.
