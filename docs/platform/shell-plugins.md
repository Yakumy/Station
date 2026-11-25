<!-- summary: Plugin lifecycle, IPC, bar placement, enable and disable, destruction and removal, FileView writes, loader traps, installed smoke checks. -->
<!-- code: Service.qml Panel.qml Bar.qml lib/BarBridge.js lib/platform/** -->
# Omarchy shell and plugin system

Dated sections are investigations, oldest first. A later one can supersede an earlier one.

## Lifecycle

| Fact | Tag |
|---|---|
| `omarchy plugin add <git-url> [--enable]` clones and validates. No install hooks, no package manager, no privileges. Plugins are added **disabled** unless `--enable`. Updates are `omarchy plugin update <id>` (fast-forward with a diff); removal is `omarchy plugin remove <id> [--yes]`. Plugins are unsandboxed and run inside the shell process. | [SRC] |
| Station 2.2's manifest adds the supported `bar` kind and `Bar.qml` entry beside its existing bar-widget and service. The stock host accepts a third-party full bar but exposes only one global position, so independent output positions require one isolated bar instance per screen. | [SRC] |
| A plugin with both kinds is loaded twice: the service from `Service.qml`, the bar widget and popout from `Panel.qml`. The popout reads the injected service object. | [LIVE] |
| `omarchy-shell shell listPlugins` prints a JSON **array**; entries have `id, name, kinds, enabled, active, canDisable, firstParty, clonedFrom`. `active` was `false` for every entry, so use **`enabled`**. | [LIVE] |
| `omarchy-shell shell ping` succeeds when the shell is up (about 80 ms). | [LIVE] |

## IPC

| Fact | Tag |
|---|---|
| A service declares `IpcHandler { target: "yakumy.station" … }`. Call it as `omarchy-shell yakumy.station <method> <arg>`. It works with the popout closed, and invalid input is rejected by validation in the method. | [LIVE] |
| `omarchy-shell shell call <id> <method> <arg>` (`shell.callIfLoaded`) reaches **loaded panels only**, never services. | [SRC][LIVE] |
| Do not use `keepLoaded` to work around routing: the host also uses it to retain services across plugin hot reloads. | [SRC] |
| QML function names cannot be reserved words: use `switchStation`, not `switch`. | [INFER] |
| The service can open or toggle its popout with `shell.summon("<id>", "{}")` / `shell.toggle("<id>", "{}")`. | [LIVE] |

## Bar placement and enable/disable

| Fact | Tag |
|---|---|
| `omarchy plugin disable omarchy.workspaces` removes the stock widget from the layout; `omarchy plugin enable omarchy.workspaces` restores it. | [LIVE] |
| **Re-enabling without placement does not return it to its old place**: it landed in `center` index 4 (the widget's manifest has no `defaultSection`, so the registry falls back to `center`). | [LIVE] |
| Bar indexes are **zero-based** and clamped to list bounds. `moveBarEntry` removes the old entry before resolving the destination. | [LIVE][SRC] |
| `omarchy bar put` is idempotent: it leaves an already-present widget where it is. **Restore with enable, then `omarchy bar move <id> --section <s> --index <i>`.** | [LIVE] |
| A stock widget that was already disabled before Station touched it stayed disabled (no lease = never enable). A leased widget restored to the newest recorded position. | [LIVE] |
| The preinstalled Display bar widget is plugin id `omarchy.monitor`; its manifest declares a `bar-widget` and the default bar places it in the right section. It can be hidden and restored through the same `omarchy plugin disable/enable` plus `omarchy bar move` commands as other bar widgets. Station records a separate ownership lease so uninstall restores it only when Station hid an enabled copy. | [SRC] |
| On 2026-10-09, `omarchy.monitor` was absent from `shell.json`'s bar layout and `listPlugins` reported `enabled:false`, while Station's `hideDisplay` setting was false and `displayLease` was null. A switch bound only to `hideDisplay` therefore appeared off even though Display was hidden, and the lease-only restore path could not show it. The switch now reflects live bar presence; an explicit Show enables the widget, while automatic startup/removal restoration remains lease-bound. | [LIVE][SRC] |
| The 2026-10-09 Quickshell `SIGABRT` cores with command line `quickshell --no-color -p /tmp/station-qml-*` came from the isolated QML compile check launched without Wayland access. Qt aborted during GUI backend initialization after `Failed to create wl_display (Operation not permitted)`; a retry with session access compiled successfully. The check now probes the Wayland socket and exits cleanly when inaccessible. | [LIVE][SRC] |

## Plugin destruction and removal

| Fact | Tag |
|---|---|
| `Component.onDestruction` fires on plugin **disable, remove, and shell restart alike**. A cleanup started from it must distinguish them. | [LIVE] |
| Working pattern: start a detached script, wait ~3 s, retry `omarchy-shell shell ping` up to 15 s, read `listPlugins`; if the plugin is `enabled` → do nothing (restart); else restore the stock widget, neutralise `monitors.lua`, clear the lease, `hyprctl reload`. Restart produced `restart-skip`; disable and remove ran cleanup after about 5 s and left default `SUPER+1` and grouped-focus bindings restored and no Station binds. | [LIVE] |
| A detached watchdog (`sleep 20; [ -e token ] && { rm token; hyprctl reload; }`) **survives `SIGKILL` of the shell**; it removed the token, reloaded at 19.99 s and restored geometry. | [LIVE] |
| Normal removal leaves an inert backup directory under the plugin tree. | [LIVE] |
| On 2026-11-14, `omarchy plugin remove yakumy.station --yes` on Omarchy 4 printed `omarchy-shell is not responding` and left every removal step undone: both leases and `appliedBinds` stayed in `state.json`, both stock widgets stayed disabled, and `station-workspaces.lua` stayed. `omarchy-shell` gives each IPC call 2 s (`OMARCHY_SHELL_IPC_TIMEOUT`), and the shell logged 17 plugin reloads for the deleted folder at that moment, so a single `listPlugins` call can time out. Which call failed was not captured. The cleanup script now retries `listPlugins` and each widget command; the retry is proven with fake commands only. | [LIVE][INFER] |

## FileView writes and reload validation

| Fact | Tag |
|---|---|
| `FileView.setText` with unchanged text does not provide a fresh `saved` acknowledgment. A recovered migration that rewrote an identical journal waited indefinitely. Incrementing a journal revision forces an acknowledged write for every attempt; wait for that acknowledgment before changing compositor state. | [LIVE][SRC] |
| Component compilation checks syntax/types but do not instantiate the service or exercise asynchronous file callbacks. Journal recovery needed a runtime test in addition to compilation. | [LIVE][SRC] |
| Plugin source reload alone did not reliably replace cached JavaScript during the compact-grid repair. Restarting the shell loaded the installed revision. Runtime binds are reinstalled asynchronously afterwards; an immediate count can temporarily be zero before returning to 36. | [LIVE] |

## Architecture refactor installed smoke (2026-11-05)

- [LIVE] The clean installed `dev` checkout advanced from `d9caad9` to `4ffa775`
  through the stock updater. A shell restart loaded a new Quickshell process.
  Shell ping succeeded. Station reached idle with the same two-output mapping.
- [LIVE] Three IPC panel open/close cycles on `HDMI-A-2` mapped two keyboard
  surfaces, then removed both. Wanted intent followed the actual layer state.
  The final panel was closed. No display/window setting was edited.
- [LIVE] Existing client identities, output/workspace placement, monitor geometry,
  per-monitor bar settings, appearance, leases and autoreload matched the baseline.
  Config errors were empty. All 36 Station bindings were registered. Their
  definitions and classifications matched the baseline. Physical keys were not tested.
- [LIVE][SRC] Normal restart bookkeeping advanced the journal revision with an
  unchanged map. Focused-menu synchronization changed shell `bar.position` from
  `right` to the focused output's saved `left` edge. Independent bar rows remained
  unchanged. This is the existing `syncFocusedBarMenu()` behavior.
- [LIVE] Known bar-edge binding and implicit `exitCode` warnings remained.
  The log contained no TypeError, ReferenceError or assignment error. This narrow
  smoke check does not prove destructive-transition unmapping, detached recovery,
  hotplug behavior or other physical outputs. Evidence remains in
  `/tmp/station-installed-m7-xw3mm3q7`.

## Service composition and feature folders (2026-11-05)

- [LIVE] Commit `0f5fa9e` split Service into owners and moved `lib/` into feature
  folders. The stock updater installed it and one shell restart loaded it. Shell ping
  succeeded. Status matched the baseline apart from `globalBarPosition`, which follows
  the focused output's saved edge.
- [LIVE] Two IPC panel cycles mapped two extra layer surfaces and removed them. Switching
  from station 2 to 1 and back moved both outputs together. Invalid arguments returned
  `invalid`. An unchanged `setMode extend` preview armed the token and ran the countdown,
  and Revert returned to `idle`. Clients, geometry and source file hashes did not change.
  This does not test a topology change, physical keys or hardware transitions.
- [LIVE] The log contained no TypeError or ReferenceError. The known `exitCode` and panel
  edge binding warnings remained. Quickshell logs `Module path ... is outside of the
  config folder` once per plugin directory, without effect.
- [LIVE] **Trap:** several directory imports under one QML qualifier fail under the real
  Quickshell loader with `X is not a type`, while offscreen `qmltestrunner` harnesses
  pass. Give each directory its own qualifier. Only `test/lint/compile-qml.py` detects it.
