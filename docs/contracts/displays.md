<!-- summary: Modes, geometry, the marked block in monitors.lua, preview, evacuation, Keep and Revert, the internal Off flag, enabling outputs, screen recovery. -->
<!-- code: lib/displays/** lib/platform/Transactions.js lib/platform/Hypr.js -->
# Display edits

## Modes

- **Extend:** enabled outputs form one desktop.
- **Mirror:** enabled outputs mirror the source. The editor keeps each output's
  independent geometry from the marked block, because sinks report the source's
  coordinates.
- **Single:** the other outputs are disabled and windows merge onto the target.

Never leave zero real outputs. If the Single target disappears, fall back to Extend.
Always send explicit `disabled` and `mirror`, because `mirror = ""` is the only way to
clear a previous mirror.

## Geometry

The canvas uses Hyprland logical coordinates: `w = pixelW / scale`, with width and
height swapped for transforms 1, 3, 5 and 7. Edges snap to neighbors and to a 10-unit
grid. Parallel alignment snaps only within 20 logical units, so unequal monitors can
stay attached at any offset. When rotation, scale or resolution changes a rectangle,
keep its strongest shared edge and reposition it without overlap. Overlapping layouts
cannot be kept.

## Marked block

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
- A rule that carries geometry also carries `bitdepth = 10` when Hyprland reports the
  output's `currentFormat` as a `…2101010` format. Station keeps that depth but never
  sets it. Without the field Hyprland drives the output at 8 bits, so rewriting the
  rule without it would drop a 10-bit monitor. Rules without geometry merge into the
  existing rule and leave the depth alone. Blocks written before 4.2.1 have no field
  and still parse.

An older block at the end of the file migrates once, with a backup and a source
comparison. That upgrade applies the current Lua, which clears old runtime appearance
rules.

## Preview

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

## Evacuation

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

## Keep

Keep is a transaction:

1. Capture the accepted options before writing candidates.
2. Wait for both candidate save acknowledgments, not a fixed delay.
3. Compare the source with the text read before.
4. Back up as `monitors.lua.bak.<timestamp>`, keeping the last 5.
5. Save each shown output's mode, position, scale and transform as Omarchy's display
   panel choice with `omarchy-hyprland-monitor-persist`, after backing up Omarchy's
   settings file. Omarchy applies those choices after `monitors.lua` on every load, so
   a stale one undoes the edit. Mirrored and disabled outputs are skipped, as Omarchy
   skips them. An Omarchy without the command is left alone.
6. Replace the file atomically. Refuse symlinks, and change only the marked block.
7. Let Hyprland's file watcher apply it, then check `hyprctl configerrors`.

Events during Keep must not reset the draft or apply the previous mode. On success,
commit the options and take a fresh snapshot before reconciling. On failure, restore
Omarchy's panel settings file, and `monitors.lua` only if it still matches Station's
candidate, then reload. Newer external edits
survive. External editors share no lock with Station, so this is optimistic detection.

Scale (1, 1.25, 1.6, 2, 3, 4), Resolution and Refresh use the same file transaction
directly from `idle`, with no preview, watchdog or countdown. Their selections keep an
exact mode string.

## Internal monitor Off flag

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

## Enabling outputs

`hl.monitor` returns before a re-enabled output exists, so a focus sent straight after it
can answer `monitor not found`. Station retries that exact answer for up to 2 seconds,
only for an output it just enabled. Any other answer fails the preview.

Single reads back from the compositor as every other output disabled. Leaving Single
for Extend or Mirror therefore turns on **every** connected output. An output that was
switched off with its card before Single comes back on, and the user can turn it off
again.

## Screen recovery

After Keep or Revert settles, Station compares enabled non-mirrored Hyprland outputs
with Quickshell's screen list. A missing screen means the host lost its surfaces. If
another active output remains visible, Station cycles the missing output once and
restores its validated rule. It never cycles the only visible output.
