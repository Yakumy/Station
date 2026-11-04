# Station 3.0 — System authority

This is the accepted revision to the v2 synchronization and persistence contracts.
It supersedes the v2 requirement to restore saved monitor and appearance settings
on startup, reload, and hotplug. Workspace journals and transaction safety remain
required. PR #5 by Nitai is retained as an original ancestor; v3 extends that fix
from a disabled-output filter to observation of effective system settings.

## Ownership

| Setting | Authority | Station behavior |
| --- | --- | --- |
| Display enablement, mirror source, geometry, scale, rotation, mode | Applied Hyprland monitor state | Observe on reload/hotplug and every 1.5 seconds; migrate workspace bookkeeping to the actual independent outputs |
| Global gaps, Dwindle default split, rounding, window animation base speed | Hyprland options and animations | Read on startup/reload and while the panel is open; persist only an explicitly edited control |
| Bar monitor settings and focused-monitor menu position | Omarchy shell configuration | Adopt changed rows; discard superseded pending writes for those rows |
| Global blur enabled/size/passes | Hyprland | Never force or restore global values; Station owns only its bar layer rule |
| Personal keybindings | Hyprland/Omarchy bindings | Report conflicts instead of replacing personal bindings, including digit/code aliases; retain known stock replacements and explicit approval |
| Wallpaper | Omarchy when Follow Omarchy is enabled; explicit Station choice otherwise | Existing observation and opt-in wallpaper behavior retained |
| Brightness and text size | Existing Omarchy controls | Existing connector-specific reads/writes retained |
| Station IDs, preferred lanes, workspace journals, UI preferences | Station | Persist and recover independently of compositor setting observation |

A runtime terminal change appears in Station but is not written into a Lua file.
A subsequent Hyprland reload applies its files normally. `config.json` may retain
observed display values as a cache, but those values do not enforce monitor state.
DPMS/screen blanking is not display disablement. Mirrored sinks never receive an
independent workspace column, even when the source's preferred lane is higher.

## Persistent settings and personal overrides

Station's marked display block is at the **beginning** of `monitors.lua`. Personal
Lua outside the block follows it and retains final precedence under Hyprland's
normal rule semantics. Existing v2 blocks are migrated once, with a backup and
comparison against the source read before replacement. The one-time upgrade
applies the current Lua configuration, clearing old v2 runtime appearance rules;
when no block write is needed, it performs one reload for that purpose. Cached
v2 appearance preferences are not re-enforced. No arbitrary personal Lua is parsed
or evaluated by Station. New generated blocks include a bounded configuration-time
DRM presence check (cards 0–15, validated connectors, 32-byte status reads), because
`hl.get_monitors()` can be empty at cold login. With no discoverable survivor the
safe Extend fallback remains. The service does not subsequently enforce a mode.

Window control edits update only their entry in a separate marked section at the
beginning of `looknfeel.lua`. Personal settings later in that file, or later in the
main Lua load order, can override them. A read-back mismatch displays a notice;
Station shows the applied value rather than repeatedly trying to restore its
request. Editing an earlier rule in the Lua load order cannot override a later
rule: place personal overrides after Station's section or edit its section.

The v3 window controls represent **global compositor settings**. Rounding follows
`decoration:rounding`, which Omarchy also uses for shell corners. This replaces
v2's private application-rounding rule. Outer gaps no longer use Station-created
per-monitor workspace overrides. Per-window/workspace rules can still override
these global defaults; the panel is not an inspector of every client's effective
rules. The animation control reads the `windows` base leaf; editing it deliberately
sets the related window leaves together. Custom animation curves/styles are not
represented by the speed slider. External numeric values are displayed without
being rounded to a slider stop until the user edits that control.

Window sliders retain their local selection during pointer input and through the
save's applied-value read-back. Unchanged snapshots and unrelated configuration
updates cannot reset an active edit. Controls remain busy until read-back finishes,
including failed reads; then the panel adopts the last observed compositor values.
A personal override or failed save can therefore return the control to the applied
value, while successful saves do not briefly jump back to the previous setting.
Replacement-bar actions refresh their detached busy snapshot synchronously before
the host slider completes release.

Global blur now follows the user's compositor configuration. Choosing Blur on a
bar requests its layer effect but cannot override disabled global blur. Legacy
blur leases are retired without restoring stale globals.

Omarchy's generated `internal-monitor-disable.lua` flag is a shared control,
not an immutable personal override. Station observes it without changing it.
When the user enables that internal output and presses **Keep**, Station clears
only the exact recognized Omarchy Off flag as part of saving the layout. Preview,
Revert, timeout, and unrelated side-control saves leave the flag alone. Modified
or unrecognized toggle Lua is preserved.

## Transactions and conflicts

Display previews retain panel evacuation, survivor activation, window migration,
Keep/Revert, and detached watchdog protection. Explicit Mirror source changes
also use this guarded preview. Personal configuration reloads cancel a pending
preview and adopt the new topology instead of enabling its old saved target.
Stable previews also detect external runtime geometry changes through observation.
Queued Lua commands are checked against the configuration generation before they
run. Already executing compositor commands cannot be retroactively cancelled.

A save compares the source read with the file immediately before replacement.
An intervening edit fails the save. Error rollback checks that the current file
still matches Station's candidate before restoring its backup. This is optimistic
conflict detection; ordinary external editors do not share a lock with Station.
Successful writes use the watched apply and check `configerrors`; they do not
force a redundant reload. The internal-monitor toggle handoff updates two files:
it compares both sources, temporarily suspends automatic reloads, backs up and
removes the recognized flag, saves the layout, and explicitly reloads once.
It restores the prior autoreload setting on exit. Failure restores both files
only where newer external edits have not replaced them. Toggle backups use a
non-`.lua` suffix so Omarchy does not load them as active toggles.
Failed applies restore the backup and reload it.

The detached watchdog reloads current configuration, not a cached Lua copy.
Removal cleanup neutralizes mode fields in the current generated monitor rules;
it does not restore a stale geometry copy over manual edits.
Workspace migration retains original window identities and station numbers across
external topology changes, preview cancellation, and restart recovery.

## Verification and remaining hardware coverage

The regression suite covers observation without monitor writes, disabled saved
survivors, explicit Single/Mirror transitions, external reload during preview,
mirror IDs, source ordering, personal binding conflicts, cold presence guards in
isolated Lua, persistence precedence, source conflicts, and error rollback.

On 2026-11-04, the installed fix passed 236 Node tests, 23 offscreen layout
cases, QML compilation, theme-token checks, and plugin validation. The live
two-monitor regression used the same `setDisplayEnabled` handler as the card:
On → Revert retained the Omarchy Off flag; two On → Keep cycles cleared it,
stayed On across explicit reload, and reported no layout conflict. Each cycle
then ran the exact `omarchy-hyprland-monitor-internal off` command and verified
Station adopted and retained Off. Autoreload returned to its original false
value and `configerrors` was empty. Final state was restored to internal Off /
external On; `monitors.lua` matched its pre-test bytes. This did not exercise
physical pointer clicks or lid transitions.

Cold login with the new DRM guard, physical reconnects, lid behavior, simultaneous
hotplug, and three/four-monitor hardware remain manual verification items. An
isolated test is not proof of those hardware paths. Missing DRM access retains
the safe fallback rather than guessing which output can survive.

The slider regression check is `python3 tools/v3/check-window-sliders.py`.
It uses production WindowsTab and the installed host PanelSlider with isolated Qt
pointer events, covering snapshots during dragging/saving, successful read-back,
personal overrides, and failed saves. Paint tokens and the compositor service are
doubled; this does not prove physical pointer behavior in the running shell.
Node tests cover busy/read-back ordering, read failures, stale generations, and the
replacement-bar snapshot handoff. The fix passed 238 Node tests, the new pointer
regression (two cases plus setup/cleanup), the existing 23 layout cases, QML
compilation, theme-token checks, and plugin validation from an isolated export.
Physical pointer acceptance is left to the user on the updated installed plugin.

Suggested user test: edit a display or global gap in Lua after Station's block,
apply it, and confirm the panel follows; with an external display active run
`omarchy-hyprland-monitor-internal off`, confirm Station shows the internal display
Off, turn it On in Station, press Keep, and verify it stays On after reload;
repeat with Revert and timeout to confirm the Off flag remains; use a Station control and verify its saved setting
survives reload when no later personal rule overrides it; try Single/Mirror
with Keep and Revert; change bar position through the Omarchy menu.
