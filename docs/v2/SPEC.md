# Station v2 — Build Spec (final)

Plugin id `yakumy.station` for Omarchy 4 (Quattro), Hyprland 0.56.x (Lua config).
Tags: **[V]** verified on the author's machine, **[A]** assumption. Every [A] that affects architecture is eliminated in **M0** (§15) before M1 starts. Record observed results in the M0 table; do not design around an unverified assumption.

GUI reference: open `reference/gui-reference.html` in a browser. It shows layout, states and behaviour. Its colours are a preview palette only; the real plugin uses theme tokens (§11).

## 1. What Station is

A pure Quickshell plugin (QML + JS, a little generated Lua). One concept, the **Station**: switching station switches every monitor together; sending a window to a station keeps it on the same monitor; unplugging a monitor merges its windows into a surviving monitor without changing their station. A GUI arranges displays.

Non-goals: no binary, no `install.sh`, no standalone CLI, no v1 migration, no more than 3 managed monitors, no HDR/VRR/colour management, no self-update logic.

## 2. Principles

**2026-10-11 addition:** Wallpaper is a service-owned, independent feature;
see [WALLPAPER.md](WALLPAPER.md). It adds no workspace or monitor policy.

1. Install, update, remove are the stock `omarchy plugin add|update|remove`. Omarchy owns updates and review. Station performs no network access.
2. The plugin works when enabled. No init button, no wizard.
3. Station writes only: its own config and state files, and (on Keep) a marked block in `~/.config/hypr/monitors.lua`, with backup. It never edits `hyprland.lua` or `bindings.lua`.
4. Every runtime effect (binds, workspace rules, monitor runtime state) is re-applied after each `configreloaded`. Removing Station triggers an immediate reload (§10), so nothing lingers.
5. No colour, radius, spacing or font literals. Theme tokens only.
6. Every value that reaches Lua or argv is validated (§13).
7. Every asynchronous operation is generation-checked (§6).

## 2a. Three concepts that must never be mixed

| Concept        | Meaning                                                                                                                                                                                         | Where it lives                                |
| -------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------- |
| **Identity**   | Physical monitor: key from `description`; if two connected monitors share it, append `@<connector>`. Laptop panels have no serial, so model + connector. [V]                                    | config.json                                   |
| **Lane** (1–3) | The workspace column the monitor drives: `ws(station, lane)`. Persistent preference per identity.                                                                                               | config.json (preference), runtime (effective) |
| **Role label** | What the user sees: Primary / Secondary / Third. **Derived**: the ordinal of the monitor's lane among lanes currently present. If lanes {1,3} are present the labels are Primary and Secondary. | never stored                                  |

A missing lane never makes the GUI say "Primary + Third". Changing Role in the GUI swaps lanes between two physical monitors (§5.5).

## 3. Verified platform facts

| #   | Fact                                                                                                                                                                                                                                                                                                                    | Consequence                                                                              |
| --- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| 1   | [V] `hyprctl eval 'o.bind("SUPER + code:10", desc, "cmd")'` works and fires on a real keypress. JSON shows `key:""`, `keycode:0`, `dispatcher:"__lua"`, `description` set.                                                                                                                                              | Use `o.bind` via eval. Do not rely on `hyprctl binds -j` for key identity.               |
| 2   | [V] `hyprctl reload` removes runtime binds and workspace rules and resets runtime monitor changes (disabled, mirror).                                                                                                                                                                                                   | Re-apply everything after reload.                                                        |
| 3   | [V] `configreloaded` fires on reload; `omarchy theme set` fires it **twice**, ~220 ms apart.                                                                                                                                                                                                                            | Trailing debounce ~300 ms.                                                               |
| 4   | [V] Binding the same combo twice leaves two entries and both commands fire. `hl.unbind(combo)` removes all entries on it.                                                                                                                                                                                               | Unbind only under the rules in §8.                                                       |
| 5   | [V] `omarchy menu keybindings --print` lists defaults, `SUPER+1..0`, personal binds and runtime binds with correct display keys. Identical with DEBUG and fresh cache.                                                                                                                                                  | Primary conflict source. Prefix Station bind descriptions with `Station:`.               |
| 6   | [V] A runtime `hl.workspace_rule({workspace, monitor})` places a newly created workspace on that monitor; it vanishes on reload.                                                                                                                                                                                        | Apply rules before moving/focusing into a station.                                       |
| 7   | [V] One `eval` with 12 `window.move` calls, no sleeps: ~10 ms.                                                                                                                                                                                                                                                          | Batch all moves.                                                                         |
| 8   | [V] Soft disable and physical unplug: workspaces migrate to the survivor, then `monitorremoved` fires; physical unplug also shows a transient create/focus/destroy of a spare workspace within the same millisecond. Client workspace ids are unchanged.                                                                | Reconcile from a post-removal snapshot. Ignore workspace events during topology changes. |
| 9   | [V] On a 3.7 s reconnect Hyprland moved the workspace and its windows back to the returning monitor.                                                                                                                                                                                                                    | Grace delay before merging (default 5 s).                                                |
| 10  | [V] `hl.monitor({... mirror="X"})`, `{disabled=true}`, `{disabled=false}` work. Re-enabling without `mirror` keeps the old mirror; `mirror=""` clears it.                                                                                                                                                               | Always send explicit `disabled` and `mirror`.                                            |
| 11  | [V] `hl.get_monitors()` exists and worked while `monitors.lua` was parsed during a reload (returns userdata with `id,name,width,height,scale,active_workspace`; `enabled` is nil). [V, M0] On two cold compositor starts it existed but returned an empty table, both with HDMI connected and laptop-only; monitors appeared normally after startup. | Guarded block (§9). Never depend on the cold `up` set to apply Single/disable; the service applies runtime mode after monitors become available. |
| 12  | [V] `Component.onDestruction` fires on plugin disable, remove, and shell restart alike.                                                                                                                                                                                                                                 | Cleanup must distinguish them (§10).                                                     |
| 13  | [V] Re-enabling `omarchy.workspaces` without placement puts it in `center` index 4, not its old place.                                                                                                                                                                                                                  | Record and restore placement (§10).                                                      |
| 14  | [V] `omarchy-shell shell listPlugins` entries: `id,name,kinds,enabled,active,canDisable,firstParty,clonedFrom`. `active` was false for all; use `enabled`.                                                                                                                                                              |                                                                                          |
| 15  | [V] Brightness read: `omarchy-brightness-display --monitor <name>` prints percent on line 1; empty or `unavailable` = unavailable. Write: `omarchy brightness display --no-osd --monitor <name> N%`. Internal: brightnessctl; external: DDC/CI. The direct binary has **no** `--help`; never call it with unknown args. |                                                                                          |
| 16  | [V] Display plugin: `/usr/share/omarchy/shell/plugins/panels/monitor/` (`Panel.qml`, `Model.js`), kind `bar-widget`. Reference only; never edit.                                                                                                                                                                        |                                                                                          |
| 17  | [V] Shell IPC ping ~83 ms.                                                                                                                                                                                                                                                                                              | See latency target §8.                                                                   |
| 18  | [V] Lua dispatch syntax (from v1): `hl.dispatch(hl.dsp.window.move({ window="address:0x…", workspace=N, follow=false }))`, `hl.dispatch(hl.dsp.workspace.move({ workspace=N, monitor="NAME" }))`.                                                                                                                       |                                                                                          |
| 19  | [V] Omarchy 4 binds `SUPER+1..0` as `SUPER + code:10…19`.                                                                                                                                                                                                                                                               | Unbind with the same form.                                                               |

## 4. Stack and layout

QML for UI and services; plain JS modules for logic. Tests with `node --test` (lib/ has no QML dependencies).

```
yakumy.station/
├── manifest.json        # id yakumy.station, kinds ["bar-widget","service"]; copy key names from the Display manifest and PluginRegistry.qml; Panel.qml is the widget's popout entry, as in Display
├── Service.qml          # root item: IPC methods, state machine, event loop
├── BarWidget.qml        # logo + [S n]; click toggles the popout
├── Panel.qml            # Display-style popout (qs.Ui Panel/KeyboardPanel): Displays | Wallpaper | Keybindings | Settings
├── lib/
│   ├── Model.js         # lanes, roles, planners (pure)
│   ├── Hypr.js          # the only place hyprctl/eval is called; validation; Lua generators
│   ├── Binds.js         # bind table, apply, conflict checker
│   ├── MonitorsLua.js   # managed block generator/writer, Keep transaction
│   ├── Recovery.js      # preview watchdog, cleanup script templates
│   └── Store.js         # config.json / state.json load, save, migrate
└── test/
```

`barWidget.defaultSection: "left"`; on first start place it at left index 1 (next to `omarchy.menu`) with `omarchy bar`. **M0 finding:** the on-demand `panel` kind does not inject the `anchorItem` and `bar` that `KeyboardPanel` requires, so Station uses the **Display popout structure** (bar-widget + `Panel.qml`) as its primary design, with the service opening it for hotplug through the widget. M0 must prove, on an installed fixture, a rendered popout of about 680×560 with keyboard focus, Esc and outside-click closing, anchoring under the widget, and a service-driven open. If the popout cannot reach that size, reduce the layout (single column, tabs) rather than switching kinds.

## 5. Model

**2026-10-05 accepted revision:** compact numbering replaces the original fixed
three-slot grid. Station identity persists; raw workspace IDs may change when
the active display count changes.

For ordered active outputs `outputs` and `N = outputs.length`:

```js
ws(station, output) = (station - 1) * N + outputs.indexOf(output) + 1
stationOf(id, oldMap) = Math.floor((id - 1) / oldMap.outputs.length) + 1
```

There are ten stations and one to three active outputs. Single and Mirror use
one output. Two-output stations use 1/2, 3/4, 5/6, etc. There are no reserved
holes. Non-grid, named, special, pinned, and unmanaged windows are excluded from
window migration.

### 5.1 Display preferences and active order

Preferred lanes remain persistent per display identity. Still-connected
monitors retain their effective preference; a new display takes its preferred
free lane or the lowest free lane. At most three monitors are managed.
Preferences determine output order, but active slots are always dense. Thus
preferred lanes 1 and 3 become active slots 1 and 2.

### 5.2 Active mapping

The committed ordered output list is saved in `workspace-map.json`. Extend
uses enabled managed displays; Single uses its target (or a surviving fallback);
Mirror uses its source. Newly connected displays join Extend; explicit Single
keeps them out of the active map. A zero-display interval preserves the saved
mapping. Mode/enable previews migrate immediately to their temporary mapping.
The workspace journal retains the original per-window station and display until
Keep succeeds; Revert, timeout, and restart recovery restore those assignments.
Windows created during a preview retain their station through recovery.

### 5.3 Migration and recovery

Snapshot clients before any move. Decode station and old display using the
saved old mapping, including when Hyprland has already moved a disconnected
display's windows onto a survivor. Preserve each window's station and its display
if that display survives. Otherwise merge into the next surviving old display,
or the previous one; if none survive, use the new primary display.

Adding a display expands workspace IDs but keeps windows on surviving physical
displays. Returning displays start empty; merged windows do not move back.
Single workspace 3 becomes dual workspace 5 on the original primary display,
and returns to workspace 3 after collapse.

Persist a journal containing old/new maps and each window's address, PID,
initial class, station, and destination. Wait for write acknowledgment, apply
rules and address-based moves, place existing destination workspaces, verify,
and commit the new mapping. Failed or interrupted operations retain the journal.
Resume by window identity and recorded station, never by decoding partially
migrated IDs. If topology changes again, retarget the saved logical destinations.
Window commands are suspended until the mapping commit completes.

The old fixed-three-slot v2 installation receives a one-time conversion,
identified by state version 1. Subsequent starts use only the saved compact map.

### 5.4 Station existence

`existing = {1..minStations} ∪ {stations holding a grid client on a managed monitor} ∪ {stations currently displayed on a managed monitor}`. `minStations` is a setting, default 3 (1..10).

- `SUPER+n` goes to any station 1..10 (created lazily by focus). An empty non-default station that is no longer displayed stops existing.
- Arrow navigation moves to the next/previous **existing** station in the step. No wrap. At the edge: no-op.
- Window moves go to exactly `s±1` (1..10), creating it.

### 5.5 Role change and swap

Swap display preferences, then use the same journaled migration from old to new
output order. Each window retains its station and physical display, while its
workspace ID changes to the display's new dense slot.

### 5.6 More than three monitors

Station manages at most 3 enabled, non-mirrored monitors. A fourth independent monitor is **unmanaged**: the Displays panel opens with an explanation and offers Mirror or Disable. Station never disables anything by itself. Unmanaged monitors are excluded from follow-focus, lane lookup, send/move actions, reconcile, and `[S n]` derivation, and their windows are never touched.

### 5.7 Direction

`ltr | rtl` (later `ttb | btt`). Arrow keys are physical; the mapping to a station step:

```js
const AXIS = {
  ltr: { ax: "x", next: +1 },
  rtl: { ax: "x", next: -1 },
  ttb: { ax: "y", next: +1 },
  btt: { ax: "y", next: -1 },
};
function step(dirKey, dir) {
  // returns +1 next, -1 previous, null if other axis
  const a = AXIS[dir],
    k =
      a.ax === "x"
        ? { left: -1, right: +1 }[dirKey]
        : { up: -1, down: +1 }[dirKey];
  return k === undefined ? null : k * a.next;
}
```

- Navigate (`CTRL+SUPER+arrow`): see §5.4.
- Send (`SUPER+SHIFT+n`): target `ws(n, lane of the window's current monitor)`, follow. `SUPER+SHIFT+ALT+n`: same, no follow.
- Move across (`SHIFT+CTRL+SUPER+arrow`), revised to match v1.1.10: read the actual active window, attempt native directional movement, wait 20 ms and re-read that window. If native movement changed position, size, workspace or monitor, do not issue another move. Otherwise try the neighboring managed display in that physical direction. At an outer edge, use `step()` to cross a station; preserve the physical display when crossing perpendicular to the display arrangement, or enter the opposite-edge display when crossing along it. Synchronize every display in the destination station and explicitly focus the moved window. Single mode also permits station-edge fallback. Invalid, pinned, special and unmanaged windows are excluded.

### 5.8 Switch station

Apply rules for the compact mapping, then `focus` each active output's workspace, then restore focus to the previously focused monitor. One eval batch, inside a `switching` operation (§6).

### 5.9 Layout geometry

Canvas and validation use Hyprland **logical** coordinates: `w = pixelW / scale`, `h = pixelH / scale`, with w/h swapped for transforms 1, 3, 5, 7. A 3840×2160 display at scale 2 occupies 1920×1080. Snap edge-to-edge to neighbours and to a 10-unit grid. Rectangles must not overlap; overlapping layouts cannot be Kept.

## 6. Runtime behaviour

### 6.1 Operation state and generations

`Service.state ∈ idle | applyingLayout | previewing | migrating | moving | switching`, plus an integer `gen`.

- Switching uses generations to discard stale callbacks. Migration is serialized and journaled; concurrent topology events mark it for replanning after its current batch.
- **Self-generated events.** Before an eval that will cause monitor or workspace events (disable, mirror, mode change, switch), record `expect = {kinds, outputs, until: now + 2 s}`. Matching events inside the window never start a topology operation and never trigger follow-focus.
- A **real** topology event during `previewing` cancels the preview (rollback, §9), then is handled normally.
- A monitor removed during `switching` aborts the switch. During migration it marks topology dirty; recovery retains the recorded station identities.

### 6.2 Start

Load config/state → recovery check (§9 stale preview token → rollback) → read monitors/clients → validate environment (Hyprland ≥ 0.55 Lua, Quickshell `Hyprland` module) → assign lanes → apply (binds, rules, monitor runtime state) → stock widget lease (§10) → reconcile → one-time toast "Station is active. SUPER+1…0 now switch stations."

### 6.3 Events

- `configreloaded`: trailing debounce 300 ms, then re-apply binds, rules and monitor runtime state, then reconcile.
- `monitoradded*`: cancel removal grace, refresh displays, reapply the saved mode, and migrate to the resulting compact map. Open the panel on Displays. In Single mode a new monitor stays off.
- `monitorremoved*`: retain the old mapping during `graceMs` (default 5000). A reconnect cancels compaction. Otherwise reapply the saved mode to survivors and run a journaled migration, then show the retained station.
- If the Single target (or every enabled monitor) disappears: fall back to Extend on whatever is connected.
- **Follow focus** (default on, setting): on `workspace.active` (100 ms trailing debounce), act only when `state === idle` and no topology change happened in the last 500 ms; if the focused managed monitor's station differs from another present monitor's, `showStation` it. Re-read state before acting. Suppressed entirely while `switching`, `migrating`, `moving`, `applyingLayout`, `previewing` (`syncInProgress`).

`[S n]` = station of the focused managed monitor's active workspace.

## 7. Modes

- **Extend:** enabled displays form one desktop; checkmarks enable/disable individual displays.
- **Mirror:** all enabled mirror the primary (lowest present lane).
- **Single on k:** others disabled; journaled migration merges each station onto k and compacts IDs to 1–10. Back to Extend expands IDs and retains windows on k.
- Mode is global (Mode dropdown beside Direction). Mode and enabled set are config preferences, re-applied at start and after reload, and written into the guarded block (§9).
- Never leave zero enabled monitors: if the saved enabled set has none connected, enable all connected.
- Always send explicit `disabled` and `mirror`. [V]

## 8. Keybindings

| Action                               | Default                         | Replaces                                                                                                                                                                                                                                            |
| ------------------------------------ | ------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Switch to station n                  | `SUPER + 1…0`                   | Omarchy workspace switch (`SUPER + code:10…19`)                                                                                                                                                                                                     |
| Move window to station n (follow)    | `SUPER + SHIFT + 1…0`           | Omarchy move to workspace                                                                                                                                                                                                                           |
| Move window silently                 | `SUPER + SHIFT + ALT + 1…0`     | Omarchy move-window-silently (default; confirmed live and in `default/hypr/bindings/tiling.lua`)                                                                                                                                                    |
| Station to the left / right          | `CTRL + SUPER + ←/→`            | Omarchy "Move grouped window focus left/right" (intentional replacement; author approved 2026-10-04). Applied automatically so Station navigation works on installation. |
| Move window across monitors/stations | `SHIFT + CTRL + SUPER + arrows` |                                                                                                                                                                                                                                                     |
| (unbind only)                        | `SUPER + SHIFT + ALT + ←/→`     | Omarchy "move workspace to monitor" (breaks lane mapping)                                                                                                                                                                                           |

IPC methods on the service root (explicit names; `switch` is a reserved word and invalid as a QML function name): `switchStation(n)`, `sendToStation(n)`, `sendSilent(n)`, `goDirection(d)`, `shiftWindow(d)`, `togglePanel()`. All arguments are strings validated against enums/integers. Command: `omarchy-shell yakumy.station <method> <arg>`, a **service-owned `IpcHandler`** with target `yakumy.station`. (`omarchy-shell shell call` only reaches loaded panels, not services; do not use `keepLoaded` to hide this, since the host also uses it to retain services across hot-reloads.) Description: `Station: <label>`.

**Apply rules (this replaces any blanket "unbind then bind"):**

- `hl.unbind(combo)` is allowed only for (a) intentional replacements (the Omarchy defaults in the table), (b) combos the user approved with "Replace and unbind it", (c) combos Station itself applied earlier, recorded in `state.appliedBinds` (this makes a plain shell restart idempotent, since runtime binds survive it). Anything else must never be unbound.
- A combo with an unresolved conflict is **not applied**.
- Otherwise bind once per config generation (tracked by a reload counter). Never apply the same set twice in one generation.

**Latency target:** measure press-to-station-switch end to end. Initial requirement p50 < 120 ms, p95 < 180 ms; optimise from measurements.

**Conflict checker**, in order:

1. `omarchy menu keybindings --print`: parse `<keys> → <description>`; normalise (split on spaces and `+`, upper-case, `CONTROL`→`CTRL`, modifier set + one key token).
2. `hyprctl binds -j`: modmask + key for plain-key entries only (cross-check).
3. Fallback: regex scan of `~/.config/hypr/bindings.lua` for literal `"MODS + KEY"`.

Ignore entries whose description starts with `Station:`. Statuses:

- **Intentional replacement** (amber): applied automatically; tell the user what it replaced. The set is exactly: `SUPER+1…0`, `SUPER+SHIFT+1…0`, `SUPER+SHIFT+ALT+1…0` (all Omarchy defaults), `CTRL+SUPER+←/→` (Omarchy grouped-window focus; author-approved replacement), and the unbind-only `SUPER+SHIFT+ALT+←/→`. Nothing else is ever added to it automatically.
- **Conflict** (red): shown with the owner and "Pick another key" / "Replace and unbind it" (stored and re-applied after reloads; warn that unbind removes every entry on that combo).
- **Free**: only when source 1 succeeded and nothing matched.
- **Unverified**: source 1 failed or is empty. The fallback can add conflicts but **never** turns unknown into free. Unverified binds are applied with a visible badge.

The Keybindings tab label turns red with a count badge while any conflict is unresolved. Key entry is a modifier-toggle + key picker (raw capture cannot see combos Hyprland already consumes).
The picker uses ordinary buttons, key events and a non-editable special-key
menu, never TextInput/TextField/TextEdit or clipboard access. Capture accepts
an allowlisted key pressed alone; modifier chips define the combination.
Escape cancels capture, Tab leaves capture, and the special-key menu offers
both keys. Apply is explicit; capturing Return or Space must not save the edit.
Hiding the editor, changing tabs, closing the panel or losing capture focus
stops capture. Cancel discards the edit without changing saved bindings.

## 9. `monitors.lua` managed block, preview and Keep

### 9.1 Block

```lua
-- >>> station (managed; edited by the Station panel) >>>
local up = {}
if type(hl.get_monitors) == "function" then
  local ok, list = pcall(hl.get_monitors)
  if ok and type(list) == "table" then
    for _, m in ipairs(list) do
      local ok2, name = pcall(function() return m.name end)
      if ok2 and type(name) == "string" then up[name] = true end
    end
  end
end
-- Single mode on HDMI-A-2: one combined rule per output on either path.
if up["HDMI-A-2"] then
  hl.monitor({ output = "HDMI-A-2", mode = "2560x1440@144.00Hz", position = "1920x0", scale = 1, transform = 0, disabled = false, mirror = "" })
  hl.monitor({ output = "eDP-1", mode = "1920x1200@60.00Hz", position = "0x0", scale = 1, transform = 0, disabled = true, mirror = "" })
else
  -- Empty cold discovery or missing survivor: saved geometry in safe Extend.
  hl.monitor({ output = "eDP-1", mode = "1920x1200@60.00Hz", position = "0x0", scale = 1, transform = 0, disabled = false, mirror = "" })
  hl.monitor({ output = "HDMI-A-2", mode = "2560x1440@144.00Hz", position = "1920x0", scale = 1, transform = 0, disabled = false, mirror = "" })
end
-- <<< station <<<
```

- Failure, a missing function, or an empty list must never disable a display or break config evaluation. Never emit `disabled = true` unguarded; never disable the last up monitor.
- Output names must match `^[A-Za-z0-9_.:-]{1,64}$` and are emitted through an escaping serialiser. EDID text never goes into the file. `mode` values must be an exact element of the monitor's `availableModes`; the spelling `hl.monitor` accepts is an M0 item, not inferred from JSON.
- [V, M0] Last rule for an output wins; place the block at the end. If rules for the same outputs exist outside the block, tell the user.
- [V, M0] Cold evaluation can return an empty `hl.get_monitors()` table even when displays are connected. In that case the block emits no guarded `disabled = true`; the service applies the saved runtime mode after monitor discovery. This safety fallback may briefly start in Extend rather than risking a black screen.
- **2026-10-10 repair:** every saved layout has a mutually exclusive fallback
  that applies its saved resolution, position, scale and transform with outputs
  enabled and unmirrored when its survivor guard fails. Geometry must not wait
  for a later reload. On warm reload, execute only the combined final-state
  rules, never a geometry prepass followed by disabling/mirroring. Existing
  managed blocks need regeneration through the safe file transaction; updating
  the generator alone does not rewrite an already saved block.

### 9.2 Preview and crash-safe rollback

1. Before any preview, write `~/.local/state/omarchy/station/preview.token` and start a **detached watchdog** from a fixed template with positional arguments only: `sh -c 'sleep "$1"; [ -e "$2" ] || exit 0; age=$(( $(date +%s) - $(stat -c %Y "$2") )); [ "$age" -lt "$1" ] && exit 0; rm -f "$2"; hyprctl reload;' sh 20 <tokenpath>`. No daemon, no root. The watchdog belongs to the preview that armed it: the arm step re-touches the token before every apply, so a token younger than the sleep window means a newer preview owns the session and this one stands down; only a token untouched for the full window reverts. Without that, a session longer than the window would be rolled back by the first preview's watchdog while the user was still editing.
2. Apply the preview at runtime, snapshot the resulting topology, and run journaled migration using the preview's mode/enable settings. Before disabling or mirroring the output that owns an open panel, close its keyboard-focused layer surface and wait for an acknowledgement after unmap; enable a disabled destination if necessary, focus the surviving non-mirrored output, then apply the remaining monitor rules. Reopen the panel on that output only after compositor success. Revert performs the same evacuation/enable/focus ordering before a saved Single/Mirror reload. A missing close acknowledgement aborts instead of removing the output. Once migration and focus complete, renew the recovery token/watchdog and show the full 12 s Keep/Revert countdown. While applying/migrating, edits and Keep/Revert are briefly disabled and the footer reports progress.
3. Revert, or timeout, restores previous runtime state and removes the token.
4. At shell start, a stale token means a crashed preview: roll back immediately with `hyprctl reload`. A `preview` baseline in `workspace-map.json` also restores original window ownership, even if the detached watchdog already consumed the token. Clear this baseline only after Keep or completed recovery.
5. **The topology draft stays editable while confirmation is pending** (`draftEditable` = `(idle | previewing) && !previewBusy`): drag, rotate, mode and enable join the same session. Role swaps and the Scale/Resolution/Refresh side controls remain idle-only. `previewBefore` and the original per-window baseline are captured once, so Revert returns to the start of the session. Each new topology apply pauses the countdown until migration completes.

### 9.3 Keep is a transaction

preview → **Keep** → backup (`monitors.lua.bak.<unix-ts>`, keep last 5) → atomic write (temp file + rename, refuse symlinks, markers only) → watched Hyprland apply → `hyprctl configerrors`.

Capture accepted mode/target/enabled settings before writing candidates. Wait for
both FileView save acknowledgments (unchanged text is already ready), not a fixed
delay. Monitor/reload events during Keep must not reset the draft or apply the
previous saved mode. On success commit the captured options, then take a fresh
snapshot before runtime reconciliation. Earlier rules mentioning the same output
are not errors: the managed block is deliberately last.

Scale, Resolution, and Refresh use the same backup/atomic-write/error-check
transaction directly from idle, without applying a temporary runtime preview,
arming the watchdog, or showing Keep/Revert. The watched `monitors.lua` move is
their only deliberate compositor apply. Brightness and Text size keep using
their dedicated Omarchy commands and do not enter this transaction.

- Errors present: restore the backup, reload again, restore runtime state, show the error. Keep has **not** succeeded.
- Clean: remove the watchdog token, write config.json, **also write `~/.local/state/omarchy/station/monitors-block.plain.lua`** (the same block with geometry/scale/rotation/mode only: no guard, no `disabled`, no `mirror`; used by the removal cleanup in §10.2), return to `idle`; Station re-applies after the reload event.

## 10. Bar widget and removal

### 10.1 Stock widget leases

`state.stockLease = { wasEnabled, section, index, disabledByStation }`.
`state.displayLease` has the same shape for `omarchy.monitor`.

- On each activation (if Settings "Hide Omarchy's workspace indicator" is on, default): if `omarchy.workspaces` is enabled, capture its current placement (`section`, `index`), set `wasEnabled=true`, `omarchy plugin disable omarchy.workspaces`, `disabledByStation=true`. If it is already disabled and no lease exists, record `wasEnabled=false`; **Station never enables it.** If a lease exists, keep it.
- Restore only when `disabledByStation && wasEnabled`: `omarchy plugin enable omarchy.workspaces`, then `omarchy bar move omarchy.workspaces --after yakumy.station` so it comes back **behind** the Station widget rather than in the pre-lease spot between the Omarchy menu mark and Station (re-enabling alone lands in `center` index 4 [V]). If `--after` fails because Station is off the bar, fall back to `omarchy bar move omarchy.workspaces --section <s> --index <i>`, the captured pre-lease placement. Clear the lease afterwards. **M0 correction:** `bar put` deliberately leaves an already-present widget in place; after enable, use `bar move` to restore placement.
- Settings "Hide Omarchy's Display icon" is off by default. Its switch reflects the widget's actual bar presence as well as Station's saved preference. When enabled, Station applies the same ownership rule to `omarchy.monitor`: record whether it was enabled and its exact section/index, then disable it. An explicit click to show enables the widget and restores its recorded placement (or the stock right-side placement when no lease exists). Startup and removal restore only a widget Station disabled; one that was already disabled stays disabled until the user explicitly shows it.
- Changing either hide setting gives an open Station panel a short transfer window while the bar layout rebuilds. On startup, a saved lease whose setting is now off is restored, covering interruption between saving the setting and completing the enable/move commands.
- Do **not** use `clonedFrom` as a replacement mechanism; Station is not a clone of that plugin.

### 10.2 Cleanup after disable/remove

`Component.onDestruction` fires on disable, remove **and** shell restart [V], so it starts a detached script from a fixed template with positional, validated arguments (`section` ∈ `left|center|right`, `index` and `wasEnabled` integers):

1. Sleep 3 s; wait up to ~15 s for `omarchy-shell shell ping` (the shell may be restarting).
2. If the shell answers and `listPlugins` shows `yakumy.station` with `enabled` true: do nothing (restart case).
3. If it is absent or disabled: restore each stock widget Station leased (`omarchy.workspaces` and optionally `omarchy.monitor`); **neutralise the managed `monitors.lua` block** (replace everything between the markers with `~/.local/state/omarchy/station/monitors-block.plain.lua`, the geometry-only copy Station keeps in sync in §9.3, using a fixed `awk` template, a timestamped backup and an atomic `mv`; do nothing if the markers or the plain file are missing). This keeps the user's arranged layout but removes every `disabled`/`mirror` rule and the guard, so Single or Mirror mode cannot outlive the plugin. **Then run `hyprctl reload`**. Runtime binds and workspace rules outlive the QML objects until a reload; `omarchy plugin remove yakumy.station` must leave `SUPER+number` and normal Hyprland behaviour working immediately.
4. If the shell never answers, do nothing. Troubleshooting note in the docs: run `hyprctl reload`.

[A] exact `listPlugins` JSON shape and presence of `jq`: M0.

### 10.3 Panel survives a widget rebuild

The bar rebuilds Station's widget whenever its layout entries change (a plugin enable/disable, `omarchy bar move`) and whenever an output reconfigures (§9.3 expects `monitorremoved`/`monitoradded` for a moved display). The popout is a child of that widget, so it goes down with it: measured as the panel simply vanishing while the user is still in the Displays layout or the Settings tab.

The intent therefore lives on the service, which outlives the widget: `panelWanted` is written on every `opened` transition. A transition that lands while the service binding is still empty is held (`intentPending`) and replayed when it resolves instead of dropped, since an open recorded nowhere leaves a rebuilt widget convinced the panel is closed. Destruction never writes the flag, so a rebuilt widget starts up seeing `true` and asks the service to `openPanel()`; every real close (Esc, outside-click, `shell.hide`) writes `false` and cancels the retry, so the user's close still sticks.

One close is not a dismissal: `closeForPopoutSwitch`. The bar hands the popout to the newer copy of the widget it just built and closes the old one through that path while the old copy's destruction is still deferred — measured, the close landed 2 ms after the new copy had reopened the panel, and recording it left `panelWanted=false` under a window that was still on screen. From inside that close the bar has not published the new owner yet, so the decision waits for the next event-loop turn and reads state that outlives the instance: any live copy still showing means the panel is up and the switch was a hand-off, so the flag stays set; no copy showing means the user moved on to another widget's popup, so it clears (and so does `rememberedTab`).

`summon()` answers `false` until the bar has registered the slot, so the ask fires as soon as construction clears and falls back to a 30 ms retry capped at twenty attempts; it is only issued when the widget comes up with the flag already set — a shell restart starts closed because the flag is in memory. Measured end to end: the panel is back 35 ms after the layout write that destroyed it.

The open tab rides along the same way: `rememberedTab` is written on every tab switch and cleared on a real close, so a rebuilt widget comes back on the tab the user was actually using (a rebuilt instance would otherwise start on Displays), while a panel the user dismissed still reopens on Displays.

## 11. GUI

Reference: `reference/gui-reference.html`. Style follows the Omarchy Display plugin: header icon + vertically centered title; hairline-separated sections; small uppercase labels with right-aligned values; segmented boxes; list with a check on the right.

**Bar widget:** Station logo (three vertical slabs, middle filled, currentColor) after the Omarchy menu, then `[S n]`. Same height and colour as neighbours.

**Panel:** larger ~830×500 reference frame; header; tab row `Displays | Wallpaper | Keybindings | Settings` (Keybindings turns red with a badge on conflict). Compact **Direction** and **Mode** text menus sit at the far right of that same row while Displays is selected.

Displays tab:

- Left: **Layout** canvas (logical coordinates, §5.9; drag and snap; wheel/button zoom and background pan; selected outlined; borderless rotation controls diagonally outside all four corners of the selected monitor, revealed by broad square hover targets straddling those corners and kept above neighboring cards; role-number menu inside each enabled monitor; overlaps flagged; drag stays live while a preview is pending, so an arrangement can be revised without Keep or Revert first — §9.2). A red layout error appears below the canvas.
- Right: `Selected: <connector>` followed by **Brightness** (read `omarchy-brightness-display --monitor <name>` async, show unavailable state on empty/`unavailable`; write `omarchy brightness display --no-osd --monitor <name> N%`, debounced; skip disabled monitors), global **Text size** (Omarchy's seven stops and CLI), **Scale** (1x, 1.25x, 1.6x, 2x, 3x, 4x), **Resolution** and **Refresh rate**. The last three use discrete index sliders and save immediately through the direct §9.3 transaction; they never open the Keep/Revert footer. Resolution and Refresh index exact supported `availableModes` strings, not interpolated unsupported values. Refresh choices depend on the selected resolution. Their chosen values appear at the right edge of the row header.
- Footer only while a preview is pending: "Keep these settings? Reverting in N s" with **Revert** and **Keep** (Keep runs the §9.3 transaction). No Identify, no Initialize.
- Hotplug: summon the panel on Displays when a monitor is added, not when removed. A fourth independent monitor shows the §5.6 explanation.

Keybindings tab: action, key chips, status (Free / Unverified / Replaces Omarchy default / Conflict); conflict rows expand with owner and actions.

Settings tab: Hide Omarchy's workspace indicator, Hide Omarchy's Display icon, Follow focus, Panel opening position (Left at the Station bar icon, or Center on the current monitor; Left by default), Grace delay, Minimum stations, installed version with a GitHub link. Center uses the selected output's full-screen KeyboardPanel card and keeps the card clear of the bar when the monitor is too small for exact centering.

**Theme tokens** (`import qs.Commons`, `import qs.Ui`):

| Element                          | Token                                                                                                                                                     |
| -------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Panel background / border        | `Color.popups.background` / `BorderSurface` + `Border.surfaceSpec("popups","border",…)`                                                                   |
| Text                             | `Color.popups.text` in the popout; bar widget text: injected `bar.foreground` where available, else `Color.bar.text` (there is no `Color.bar.foreground`) |
| Dropdown menus and selected rows | `Color.menu.background`, `.text`, `.border`, `.scrim`, `.selectedBackground`, `.selectedText`, `.selectedBorder`                                          |
| Global fallbacks                 | `Color.foreground`, `Color.accent`, `Color.urgent`                                                                                                        |
| Active tab, selected, Keep       | `Color.accent`                                                                                                                                            |
| Conflicts, red tab               | `Color.urgent`                                                                                                                                            |
| Corners                          | `Style.cornerRadius` (never hardcode)                                                                                                                     |
| Spacing, fonts                   | `Style.space(px)`, `Style.spacing.*`, `Style.font.*`                                                                                                      |
| Buttons, dropdowns, tab strips   | reuse `qs.Ui` controls                                                                                                                                    |

Theme-token check (`node tools/v2/check-theme-tokens.mjs`): fail on any hex colour (including short and alpha forms) and on symlinks. Copy Display's **component structure**, not its raw numeric spacing or font values: wrap dimensions in `Style.space`, use `Style.font` and `Style.spacing`, and keep the shared `BorderSurface`/`Border` model. Token names above were read from the installed `Color.qml` in M0.

## 12. Install, update, delete

|         | Flow                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| ------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Install | `omarchy plugin add https://github.com/yakumy/station.git --enable`. Station works immediately.                                                                                                                                                                                                                                                                                                                                                                            |
| Update  | `omarchy plugin update yakumy.station`, then `omarchy restart shell`. Station shows its installed version only. Schema changes migrate by `version` in config/state.                                                                                                                                                                                                                                                                                                       |
| Delete  | `omarchy plugin remove yakumy.station`. The cleanup script (§10.2) restores each stock widget Station hid, including the optional Omarchy Display widget, and reloads Hyprland. The cleanup also rewrites the managed `monitors.lua` block to plain geometry (no disable/mirror/guard), so the user's layout stays but no Station mode survives. Left behind: config.json, state.json and `monitors.lua` backups (inert files). Settings offers "Remove Station block" to delete the block entirely before uninstalling. |

Files:

- `~/.config/omarchy/station/config.json`: identities and preferred lanes, mode preferences, enabled set, direction, follow-focus, grace delay, minStations, custom keybindings, hideNative, hideDisplay, panelPosition.
- `~/.local/state/omarchy/station/state.json`: last station, applied binds, workspace/display stock leases, pending transaction, version.
- `~/.local/state/omarchy/station/preview.token`.

## 13. Security

- No downloaded code, no network access, no `sh -c` with unvalidated data, no `eval` of strings built from device text. The two detached scripts are fixed templates with positional validated arguments.
- Terminology: a **connector** is the `name` field from hyprctl. It must match `^[A-Za-z0-9_.:-]{1,64}$` and may then be used as a Lua string (escaped) or an argv element (monitor ops, brightness). **EDID-derived fields** (`description`, `make`, `model`, `serial`) are untrusted: matching and display only, never interpolated into Lua, argv or file text without a proper serialiser. (Omarchy itself shipped a fix for USB device names being executed as Hyprland Lua.)
- `Process`/`execDetached` use argv arrays.
- `monitors.lua`: backup, atomic write, no symlink following, markers only.
- Logs never contain command lines with unvalidated input.

## 14. Tests

**Unit** (`node --test`):

- All transitions between the 7 non-empty present sets with random windows: station never changes, nothing left on a missing lane, plan∘plan = ∅, adds produce no moves.
- `host()` for every case in §5.3; Mirror/Single `present`; lane assignment including lane reuse across docks and the unmanaged 4th monitor; role-swap planner; direction mapping (ltr, rtl); `existing` stations.
- Conflict parser against real `omarchy menu keybindings --print` lines and modifier-order variants; "unknown never becomes free".
- `MonitorsLua` generator: golden files, bad-name rejection, guard always wraps `disabled = true`, `pcall` structure.
- Logical-size and overlap math (3840×2160 at scale 2; rotated transforms).

**Integration / manual** (each must pass before release):

1. Station disabled with no Hyprland reload in between; then normal `omarchy plugin remove`: `SUPER+number` works immediately.
2. Stock workspace widget already disabled before Station: never enabled by cleanup. Widget moved after first Station use: restored to the newest recorded place.
3. Shell crash (`kill -9`) during a monitor preview: watchdog reloads and restores the layout.
4. Station-generated disable/mirror events do not start topology operations or follow-focus.
5. Role swap with windows on all monitors: windows keep station and physical monitor.
6. Unplug during a pending preview; monitor removed during `showStation`.
7. Fourth independent monitor: unmanaged, panel opens, nothing touched.
8. Named and special workspaces; floating, fullscreen and pinned clients.
9. Rapid remove/add/remove sequences, including re-adds inside the grace window.
10. Fast reconnect under 5 s: no merge. Physical unplug: merge after grace, station preserved.
11. Theme change in Single mode: no flicker, binds and rules survive; cold boot with and without externals; two identical monitors; docks with different monitors reusing lanes.
12. Keep with a deliberately broken `monitors.lua`: backup restored, error shown.
13. Plain `omarchy restart shell`: no duplicate binds, stock widget not touched.
14. Press-to-switch latency p50 and p95.

## 15. Milestones

**M0 — assumption-elimination gate (blocks M1).** Test each item and write the observed result in the table; amend this spec where reality differs.

| #   | Item                                                                                                                                                                                          | Observed |
| --- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- |
| 1   | `hl.dsp.focus({ workspace="N" })` and `hl.dsp.focus({ monitor="NAME" })` syntax                                                                                                               | Pass: constructors and a two-monitor focus batch worked; original monitor focus was restored. |
| 2   | Service-owned `IpcHandler` target: `omarchy-shell yakumy.station <method> <arg>` with the popout closed; p50/p95 keypress-to-switch (ping alone: p50 ~80 ms)                                  | Pass: direct closed-popout IPC; 20 physical-key samples p50 66 ms / p95 68 ms (64–69 ms). |
| 3   | Display-popout structure: ~680×560 render, keyboard focus, Esc/outside-click, anchoring under the widget, service-driven open                                                                 | Pass with sizing correction: service open, anchor, focus, Esc and outside click; theme-scaled content was 567×467. |
| 4   | Cold-start `hl.get_monitors()` in `monitors.lua`; guarded block behaviour                                                                                                                     | Pass with correction: two cold sessions returned an empty table during config evaluation; connected/laptop-only monitors appeared normally afterward. Guard remains safe; service applies runtime mode. |
| 5   | Monitor rule precedence (last wins?) and block position                                                                                                                                       | Pass: last rule won at runtime and at the end of `monitors.lua`. |
| 6   | Destruction ordering on disable/remove/restart; `listPlugins` JSON shape; `jq` present; cleanup + `hyprctl reload` leaves `SUPER+n` working                                                   | Pass on fixture: restart skipped cleanup; disable/remove cleanup reloaded and restored defaults. |
| 7   | `omarchy bar put/move` semantics and index handling; `omarchy plugin enable/disable` side effects on `shell.json`                                                                             | Pass with correction: indexes are zero-based; enable then `bar move` restores placement; `put` does not relocate. |
| 8   | Watchdog survives `kill -9` of the shell and reloads                                                                                                                                          | Pass: token removed and layout reloaded/restored after 19.99 s; supervised shell returned. |
| 9   | Timing and attribution of Station-generated monitor/workspace events                                                                                                                          | Pass: controlled disable/enable/mirror sequences captured; record `expect` before eval. Concurrent physical hotplug remains an integration test. |
| 10  | `availableModes` string format and the `mode` string Hyprland accepts                                                                                                                         | Pass: exact `1920x1080@60.00Hz` accepted; JSON duplicates confirmed. |
| 11  | Behaviour with a 4th monitor (if hardware allows; else document as untested)                                                                                                                  | Untested: only two physical monitors available; permitted to remain documented. |
| 12  | Plain shell restart: existing `Station:` binds detected by description; no duplicates                                                                                                         | Pass on fixture: three before, three after; lease untouched. |
| 13  | Removal cleanup end to end with Single mode saved: block neutralised to plain geometry, all monitors back, stock widget restored in place, `SUPER+n` default again, no leftover runtime binds | Pass on fixture for disable and remove; original desktop state restored afterward. |

- **M1 core:** Model.js + unit tests, lane assignment, switch/send/silent/go/shift, bind apply with the §8 rules, reload re-apply, reconcile on removal with grace, state machine and generations, follow focus, bar widget, stock lease and cleanup.
- **M2 displays:** panel, canvas (logical coordinates), list, resolution/refresh/scale, role swap, brightness, Mode and Direction dropdowns, preview watchdog, Keep transaction, `monitors.lua` block.
- **M3 keybindings:** conflict checker, editor, red tab.
- **M4 polish:** settings tab, docs, marketplace listing and review notes.
