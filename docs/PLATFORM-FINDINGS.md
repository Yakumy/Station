# Hyprland on Omarchy 4 with Quickshell: verified behaviour

Purpose: a durable record of how this stack actually behaves, gathered while building Station v2, so a future agent does **not** re-run the same experiments. Read §0 first, then use the sections as a lookup.

## 0. How to use this document

- **Trust level.** Every entry carries a tag:
  - **[LIVE]** observed on a running system (Codex test sessions, 2026-10-04/05).
  - **[SRC]** read from installed Omarchy/Quickshell source or from Station v1/v2 code that ran on a real machine.
  - **[DOC]** stated in the official Hyprland wiki (Hyprland 0.55/0.56 Lua pages).
  - **[INFER]** reasoned from the above, not tested.
  - **[QTTEST]** production QML exercised with Qt pointer events in an isolated offscreen harness; theme painting and compositor calls are doubled. This is not a physical desktop test.
- **Do not re-run** anything tagged [LIVE] unless the fingerprint in §13 shows the stack changed.
- **Do test** the items in §12 (never covered).
- Provenance: round 1 results reached the author as a summary; rounds 2 and M0 and the cold-login and integration results as detailed reports. Raw captures lived under `/tmp/station-desktop-tests-20261004*` and `~/.local/state/omarchy/station-m0-cold/` on the author's machine and may no longer exist. This file is the durable record. Monitor serial numbers are deliberately omitted.

## 1. Environment tested

| Item | Value |
|---|---|
| Hyprland | 0.56.2 (`efb50993780079460b0cbed1363e2166a2de1d9f`), Lua configuration |
| Omarchy | 4 (branch "Quattro"), installed under `/usr/share/omarchy`, `$OMARCHY_PATH` set |
| Shell | `omarchy-shell` (Quickshell), supervised: it restarts itself after being killed |
| Tools | `jq-1.8.2` installed; `hyprctl`, `omarchy`, `omarchy-shell`, `omarchy-brightness-display` on PATH |
| Hardware | Two monitors only: a laptop panel (`eDP-1`) and one external HDMI monitor (`HDMI-A-2`). **Three- and four-monitor behaviour was never observed.** |
| Theme | Tokyo Night was the active theme (the theme-set test simply re-applied it) |

## 2. Hyprland Lua configuration and `hyprctl eval`

| Fact | Tag |
|---|---|
| Since 0.55 hyprlang is deprecated; configuration is Lua. Under a Lua config the legacy `hyprctl keyword` form is rejected; runtime changes go through `hyprctl eval '<lua>'`, which prints `ok` on success. | [DOC][LIVE] |
| After any Lua config change validate with `hyprctl reload` then `hyprctl configerrors` (empty output = clean). Station's Keep transaction sleeps 1 s between reload and `configerrors`. | [SRC] |
| One `eval` can contain many statements joined with `; `. Twelve `window.move` dispatches in a single eval, no sleeps, completed in about 10 ms including process and IPC overhead. | [LIVE] |
| Dispatch syntax that works (used by v1 for a month and by v2): `hl.dispatch(hl.dsp.window.move({ window = "address:0x…", workspace = N, follow = false }))`, `hl.dispatch(hl.dsp.workspace.move({ workspace = N, monitor = "NAME" }))`, `hl.dispatch(hl.dsp.dpms({ action = "off", monitor = "NAME" }))`. | [SRC][LIVE] |
| Focus constructors accepted and working: `hl.dsp.focus({ workspace = "N" })` and `hl.dsp.focus({ monitor = "NAME" })`. A two-monitor batch focused one workspace per monitor and then restored focus to the original monitor. | [LIVE] |
| The `hl` table can be enumerated with `pairs(hl)` from an eval (write results to a file with `io.open`). `hl.get_monitors` is present. | [LIVE] |
| `hl.get_monitors()` returns a Lua table of userdata (`HL.Monitor(<id>:<name>)`). Readable fields: `id`, `name`, `width`, `height`, `scale`, `active_workspace` (userdata `HL.Workspace`); position and size are tables; `enabled` is `nil`. It is **not** the JSON that `hyprctl` returns. | [LIVE] |
| Omarchy provides an `o` helper available inside `eval`: `o.bind(keys, description, action)` works there (see §3). Omarchy also has `o.window(match, rules)` for window rules (see `$OMARCHY_PATH/default/hypr/windows.lua`). Window-rule syntax changes between Hyprland versions: always read the current wiki before writing rules. | [LIVE][SRC] |
| Omarchy user config lives in `~/.config/hypr/` (`hyprland.lua`, `bindings.lua`, `monitors.lua`, `input.lua`, `looknfeel.lua`, `autostart.lua`). `omarchy refresh hyprland` resets them to defaults. Never edit `/usr/share/omarchy`. | [SRC] |
| Hyprland hot-reloads config on save. `hyprctl reload` forces it. **A reload clears all runtime state** (§3, §4, §5). | [LIVE] |

## 3. Keybindings

| Fact | Tag |
|---|---|
| `hyprctl eval 'o.bind("SUPER + code:10", "desc", "notify-send x")'` returns `ok`; a **real physical** Super+1 press fired it. | [LIVE] |
| `hyprctl binds -j` reports Lua binds with `dispatcher: "__lua"`, an opaque `arg` (an id such as `17`), `modmask` (SUPER = 64), and `description`. For `code:` binds `key` is `""` and `keycode` is `0`; for a named key such as `F11` `key` shows `"F11"`. **The JSON cannot tell you which keycode a Lua bind uses.** A `jq` filter on `key == "code:10"` or `"10"` matches nothing. | [LIVE] |
| `hl.bind("SUPER + code:10", …)` through the raw API produced an entry with empty key and keycode 0; the Omarchy wrapper `o.bind` is what Omarchy itself uses and what works. | [LIVE] |
| Synthetic keypresses (virtual input) did **not** trigger binds in the test harness. Test bindings with a human keypress. | [LIVE] |
| `hyprctl reload` removes runtime binds (both `hl.bind` and `o.bind`). `configreloaded` follows; re-apply afterwards. | [LIVE] |
| **Binding the same combo twice leaves two entries and both commands fire** (A then B). `hl.unbind(combo)` removes **all** entries on that combo. `hl.unbind` followed by `o.bind` leaves exactly one. | [LIVE] |
| On this Lua provider, use the **registered modifier spelling/order** when unbinding. `CTRL + SUPER + LEFT` left the stock `SUPER + CTRL + LEFT` grouped-focus binding present; matching the stock spelling removed it. Station now uses `SUPER + CTRL + LEFT/RIGHT` for those intentional replacements. | [LIVE] |
| Station's direct `hl.bind(combo, hl.dsp.exec_cmd(command), { description = ... })` path is working on this installation. This supersedes any inference from the earlier raw-bind registration probe that `hl.bind` itself cannot work. The user confirmed the repaired arrows with real keys on 2026-10-05. | [SRC][LIVE] |
| v1.1.10 directional movement first asks Hyprland to move the active window natively. A native tiled move can change position or size without changing workspace/monitor; compare all four after the settle delay before issuing a fallback move. Read `hyprctl activewindow -j` for the actual focus, then track that window by address and identity. | [SRC][LIVE] |
| Omarchy 4 binds workspace keys in a loop with keycodes: `SUPER + code:10…19` switch workspace, `SUPER + SHIFT + code:10…19` move window, `SUPER + SHIFT + ALT + code:10…19` move window silently. `CTRL + SUPER + ←/→` is "Move grouped window focus left/right". `SUPER + SHIFT + ALT + ←/→` moves a whole workspace to another monitor. Source: `$OMARCHY_PATH/default/hypr/bindings/tiling.lua`. 55 declarations containing SUPER and CTRL exist in the defaults. | [LIVE][SRC] |
| **`omarchy menu keybindings --print` is the reliable listing.** It shows defaults, `SUPER + 1…0`, the user's `bindings.lua` entries, **and runtime binds**, with the real display key even when `hyprctl` shows `key:""`. Baseline 227 lines (228 with one extra runtime bind); output identical with `DEBUG=1` and with an empty `XDG_CACHE_HOME`. Format example: `SUPER + 1                           → description`. It uses plain `hyprctl binds` plus a Lua-source-derived cache. Upstream has had an open issue where a scan can die partway so user binds are missed; it did not occur on the test machine. | [LIVE][SRC] |
| Station v2 installed exactly 36 binds (consistent with the action table: 10 switch + 10 send + 10 silent + 2 navigate + 4 move-across; the per-action breakdown is arithmetic, only the total was reported); after a plain shell restart the count stayed 36 with no duplicates. | [LIVE] |
| Hyprland main (after 0.56.2) is expected to report Lua binds differently from `__lua`. Re-check `hyprctl binds -j` shape after upgrades. | [INFER] |
| Physical keypress to completed station switch (compositor bind → timestamp wrapper → `omarchy-shell` IPC → service → finished Hyprland eval), 20 samples: p50 66 ms, p95 68 ms, range 64–69 ms. Shell ping alone, 20 samples: p50 79.75 ms, p95 87.16 ms (ping carries extra overhead). | [LIVE] |

## 4. Workspaces and rules

| Fact | Tag |
|---|---|
| A runtime `hl.workspace_rule({ workspace = "N", monitor = "NAME" })` places a **newly created** workspace on that monitor (tested with a fresh number, `500005`). | [LIVE] |
| The rule **does not move an existing workspace**. Apply rules before the first focus or move into a station. | [LIVE] |
| Runtime workspace rules vanish on `hyprctl reload`. | [LIVE] |
| Empty workspaces are destroyed by Hyprland; a spare workspace can be created and destroyed in the same millisecond during an unplug (see §6). | [LIVE] |
| `hyprctl clients -j` gives each client `address`, `workspace.id`, `monitor` (numeric id), `pinned`. After a monitor is removed, client workspace ids are unchanged and only the monitor id changes (e.g. 1 → 0). | [LIVE] |
| Station's original fixed three-lane grid was superseded on 2026-10-05 by the accepted compact mapping: `workspace = (station − 1) × activeWidth + slot`. Single/Mirror width is one; Extend width is the managed active-output count. The durable mapping records output order. Special and named workspaces and pinned windows are excluded from migration. | [SRC] |
| Resolve a client's numeric `monitor` against the current `hyprctl monitors all -j` entries' **`id`**, then use the connector name. Monitor IDs are not Station lane numbers or array indexes. The key repair required this conversion for both client snapshots and `activewindow`. | [LIVE][SRC] |
| When compact numbering reuses an existing destination workspace, set its rule **and explicitly move that workspace to the intended monitor**. Window moves into an existing workspace alone inherit its previous physical placement. The local upgrade audit confirmed preservation of each window's physical display and station after adding this step. | [LIVE][SRC] |

## 5. Monitors

| Fact | Tag |
|---|---|
| `hl.monitor({ output, mode, position, scale, transform, mirror, disabled, … })`. `mode` accepts `"WxH@R"`, `"preferred"`, `"highres"`, `"highrr"`, `"maxwidth"`. `output` may be a name or `desc:<description>`; an empty output defines a fallback rule. | [DOC] |
| Position is a virtual layout in an inverse-Y system; negative values are allowed (`-1920x0` is left, `0x-1080` is above). | [DOC] |
| `hyprctl monitors all -j` lists enabled and disabled monitors. Fields used: `name`, `description` (e.g. `<make> <model> <serial>`), `make`, `model`, `serial`, `transform`, `disabled`, `mirrorOf` (`"none"` or the numeric id as a string, e.g. `"0"`), `availableModes`, geometry. The laptop panel has an **empty serial**; its identity falls back to model + connector. | [LIVE] |
| `availableModes` contains duplicates and near-duplicates (e.g. `1920x1080@60.00Hz`, `1920x1200@59.88Hz`). `hl.monitor` **accepted the exact reported spelling** `1920x1080@60.00Hz` with no config error and preserved the refresh. Deduplicate for display only; keep one exact allowlisted string per choice. | [LIVE] |
| `mirror = "<output>"` works. **Re-enabling a monitor without a mirror field keeps its previous mirror rule**; send `mirror = ""` to clear it. Always send explicit `disabled` and `mirror` fields. | [LIVE] |
| `disabled = true` and `disabled = false` work at runtime. | [LIVE] |
| **`hyprctl reload` resets runtime monitor changes** (disabled and mirror return to what the config says). Therefore mode state must be re-applied after every `configreloaded`. | [LIVE] |
| **Precedence: with two rules for the same output, the last one wins**, both inside one runtime eval and when a marked block is appended at the end of `monitors.lua`. | [LIVE] |
| Software disable of a monitor: workspaces and windows migrate to the survivor first, **then** `monitorremoved` fires. | [LIVE] |
| Station v1 used `dpms off` for single mode; v2 uses `disabled = true`. | [SRC] |
| On 2026-10-08, while switching Station Extend/Mirror/Single, Qt clients (including Omarchy shell) twice logged `There are no outputs - creating placeholder screen` (00:05:51 and 00:06:30 local). At 00:06:43 the shell crashed with SIGSEGV in `QtWaylandClient::QWaylandWindow::setGeometry` during xdg-toplevel configure. This is the same stack and zero-output signature as [Quickshell issue #1133](https://github.com/quickshell-mirror/quickshell/issues/1133). The local core confirms one crash; the earlier zero-output episodes are not themselves proof of two more crashes. | [LIVE] |
| Before the repair, Station's runtime Single rules followed connector enumeration, so switching the sole active output from `eDP-1` to `HDMI-A-2` could disable `eDP-1` before enabling `HDMI-A-2`. Mirror rules could likewise mirror a live output to a source not yet enabled. The preview also sent geometry rules for every monitor on a mode-only edit. These are plausible sources of the observed zero-output transition, although the core does not identify which `hl.monitor` call preceded it. The repaired rule order enables the Single destination or Mirror source first and disables outputs last; mode-only previews omit geometry rules. | [SRC][INFER] |
| During repeated previews, the expected monitor-event list was calculated from the original preview snapshot, not the most recently applied preview. A second mode change could therefore classify its own `monitoradded`/`monitorremoved` as external hotplug and cause a reload while previewing. The repair compares each mode preview with the last applied mode state. | [SRC] |

## 6. Events (Hyprland socket2 and Quickshell)

| Fact | Tag |
|---|---|
| Quickshell exposes socket2 as `Hyprland.rawEvent`; in QML: `Connections { target: Hyprland; function onRawEvent(event) { … event.name … } }`. Verified in the running v2 service. | [LIVE] |
| Event text forms seen: `monitorremoved>>NAME`, `monitorremovedv2>>ID,NAME,DESCRIPTION`, `monitoraddedv2>>ID,NAME,DESCRIPTION`, `moveworkspace>>WS,MONITOR`, `moveworkspacev2>>ID,WS,MONITOR`, `createworkspace>>N`, `workspace>>N`, `destroyworkspace>>N`, `focusedmon>>MONITOR,WS`, `configreloaded>>`, `closelayer>>omarchy-bar`. | [LIVE] |
| **Physical unplug, observed order** (60 s clean run; everything within about half a millisecond): `createworkspace>>3`, `workspace>>3`, `moveworkspace>>1,eDP-1`, `destroyworkspace>>3`, `monitorremoved>>HDMI-A-2`, `monitorremovedv2`. About 14 ms later `closelayer>>omarchy-background`, ~90 ms after that `closelayer>>omarchy-bar`. No `configreloaded`, no `monitoradded` during the 60 s. | [LIVE] |
| The spare workspace `3` is transient (created, focused, destroyed in the same millisecond) and absent from before and after snapshots. Follow-focus logic that reacts to `workspace>>` during a topology change will chase it. | [LIVE] |
| **Fast reconnect (3.7 s):** `monitoradded` came with Hyprland itself moving the workspace and its windows **back** to the returning monitor (`moveworkspace>>1,HDMI-A-2`). A merge before that point would have been undone. Hence the 5 s default grace delay. | [LIVE] |
| `hyprctl reload` emits one `configreloaded`. `omarchy theme set <name>` (even re-applying the same theme) emits **two**, about 220 ms apart. Use a trailing debounce of about 300 ms. | [LIVE] |
| Software disable emits focus and workspace migration then `monitorremoved`; enable emits `monitoradded`; mirror emits workspace events. A Station-generated eval therefore must record an "expected events" window **before** the eval. | [LIVE] |
| Unrelated physical hotplug happening while a Station-generated eval is in flight was **not** tested (see §12). | — |

## 7. Cold start and boot

| Fact | Tag |
|---|---|
| During `monitors.lua` evaluation at **cold compositor start**, `hl.get_monitors` exists but returns an **empty table** (two sessions: external connected; laptop-only). Monitors appear normally afterwards. | [LIVE] |
| Therefore a guarded block that disables monitors only when `up[name]` is true will emit **no** disable at login. It is fail-safe, but Single/Mirror mode cannot be enforced from the file at boot: the service applies saved mode once monitors are visible, so the first moments may be in Extend. | [LIVE] |
| On a warm `hyprctl reload`, `hl.get_monitors()` during parse **does** return the connected monitors. | [LIVE] |
| Hyprland starts the shell via autostart; the shell is supervised and returns after `SIGKILL`. | [LIVE] |

## 8. Omarchy shell and plugin system

### 8.1 Lifecycle

| Fact | Tag |
|---|---|
| `omarchy plugin add <git-url> [--enable]` clones and validates. No install hooks, no package manager, no privileges. Plugins are added **disabled** unless `--enable`. Updates are `omarchy plugin update <id>` (fast-forward with a diff); removal is `omarchy plugin remove <id> [--yes]`. Plugins are unsandboxed and run inside the shell process. | [SRC] |
| Station's working manifest: `schemaVersion 1`, `id`, `name`, `version`, `kinds: ["bar-widget","service"]`, `entryPoints: { "barWidget": "Panel.qml", "service": "Service.qml" }`, `barWidget: { displayName, description, category, allowMultiple, defaultSection: "left" }`. | [SRC] |
| A plugin with both kinds is loaded twice: the service from `Service.qml`, the bar widget and popout from `Panel.qml`. The popout reads the injected service object. | [LIVE] |
| `omarchy-shell shell listPlugins` prints a JSON **array**; entries have `id, name, kinds, enabled, active, canDisable, firstParty, clonedFrom`. `active` was `false` for every entry, so use **`enabled`**. | [LIVE] |
| `omarchy-shell shell ping` succeeds when the shell is up (about 80 ms). | [LIVE] |

### 8.2 IPC

| Fact | Tag |
|---|---|
| A service declares `IpcHandler { target: "yakumy.station" … }`. Call it as `omarchy-shell yakumy.station <method> <arg>`. It works with the popout closed, and invalid input is rejected by validation in the method. | [LIVE] |
| `omarchy-shell shell call <id> <method> <arg>` (`shell.callIfLoaded`) reaches **loaded panels only**, never services. | [SRC][LIVE] |
| Do not use `keepLoaded` to work around routing: the host also uses it to retain services across plugin hot reloads. | [SRC] |
| QML function names cannot be reserved words: use `switchStation`, not `switch`. | [INFER] |
| The service can open or toggle its popout with `shell.summon("<id>", "{}")` / `shell.toggle("<id>", "{}")`. | [LIVE] |

### 8.3 Bar placement and enable/disable

| Fact | Tag |
|---|---|
| `omarchy plugin disable omarchy.workspaces` removes the stock widget from the layout; `omarchy plugin enable omarchy.workspaces` restores it. | [LIVE] |
| **Re-enabling without placement does not return it to its old place**: it landed in `center` index 4 (the widget's manifest has no `defaultSection`, so the registry falls back to `center`). | [LIVE] |
| Bar indexes are **zero-based** and clamped to list bounds. `moveBarEntry` removes the old entry before resolving the destination. | [LIVE][SRC] |
| `omarchy bar put` is idempotent: it leaves an already-present widget where it is. **Restore with enable, then `omarchy bar move <id> --section <s> --index <i>`.** | [LIVE] |
| A stock widget that was already disabled before Station touched it stayed disabled (no lease = never enable). A leased widget restored to the newest recorded position. | [LIVE] |

### 8.4 Plugin destruction and removal

| Fact | Tag |
|---|---|
| `Component.onDestruction` fires on plugin **disable, remove, and shell restart alike**. A cleanup started from it must distinguish them. | [LIVE] |
| Working pattern: start a detached script, wait ~3 s, retry `omarchy-shell shell ping` up to 15 s, read `listPlugins`; if the plugin is `enabled` → do nothing (restart); else restore the stock widget, neutralise `monitors.lua`, clear the lease, `hyprctl reload`. Restart produced `restart-skip`; disable and remove ran cleanup after about 5 s and left default `SUPER+1` and grouped-focus bindings restored and no Station binds. | [LIVE] |
| A detached watchdog (`sleep 20; [ -e token ] && { rm token; hyprctl reload; }`) **survives `SIGKILL` of the shell**; it removed the token, reloaded at 19.99 s and restored geometry. | [LIVE] |
| Normal removal leaves an inert backup directory under the plugin tree. | [LIVE] |

### 8.5 Popout panel (UI)

| Fact | Tag |
|---|---|
| The on-demand `panel` loader does **not** inject the `anchorItem` and `bar` that `KeyboardPanel` requires, so use the **Display popout structure**: a bar widget whose entry `Panel.qml` is a `qs.Ui` popout. | [SRC] |
| Display's building blocks: `qs.Ui.Panel`, `BarIconButton`, `KeyboardPanel`, `PanelKeyCatcher`, `ScrollView`, `PanelSectionHeader`, `PanelSeparator`, themed controls. Source: `/usr/share/omarchy/shell/plugins/panels/monitor/` (`Panel.qml`, `Model.js`, manifest id `omarchy.monitor`). | [SRC] |
| The popout rendered anchored at `(5,27)` under the widget on `eDP-1`, took keyboard focus, closed on Esc and on outside click. **A requested `Style.space(680) × Style.space(560)` rendered as 567×467 logical pixels** under the active theme and scale: design to the available size. | [LIVE] |
| Offscreen Qt backend cannot load `KeyboardPanel`; component checks need the Wayland session. | [LIVE] |
| Replacing a JavaScript-array `Repeater.model` immediately destroys its delegates. The original drag release wrote X with `setDisplayValue`, then failed with `ReferenceError: root is not defined` before writing Y or calling Preview. Commit X/Y in one update and continue the transaction from a component outside the Repeater. Reproduced with the production handler in Qt's offscreen pointer harness. | [QTTEST] |
| Qt's `MouseArea.drag.target` starts moving after its drag threshold; an exact pointer displacement can therefore leave a card short of the desired edge. The repaired layout derives offsets from press/release coordinates in the canvas, keeps its transform stable during the gesture, and snaps within a theme-scaled 12-screen-pixel distance. Its fit reserves room for horizontal and vertical arrangements. | [QTTEST][SRC] |
| A `MouseArea` inside the panel's vertical `ScrollView` loses its pointer grab to the underlying `Flickable` once a drag is recognized. Quickshell then calls `onCanceled`, so the card visually moves and snaps back without the service entering Preview. Set `preventStealing: true` on draggable monitor cards. The regression harness must embed the production layout in a scrolling `Flickable`; testing the component as a bare `Item` misses this behavior. | [QTTEST][LIVE] |
| Isolated layout tests cover horizontal placement on either side, vertical placement, negative positions, repeat drags after Revert, click without Preview, edge snapping, selected-mode/scale/rotation geometry, and three large displays fitting the canvas. Scaled/rotated and three-display **hardware** behavior remain unverified. | [QTTEST] |
| A position-only preview used to evaluate the full managed monitor block, including a rule for every unchanged output. That can reconfigure the other monitor as well as the dragged one. The runtime preview now emits a rule only for each output whose position changed when mode, enablement, scale, rotation, and resolution are unchanged. Keep still writes the complete guarded block. Other edit types still use the full runtime block. | [SRC] |
| Omarchy's bar uses one surface per `Quickshell.screens` entry and wraps each bar window in `ScreenMoveRemap`. A position change can therefore remap the moved output's bar and destroy its Station widget and popout. Station cannot keep that same QML window alive from inside the plugin; it records the panel's output and tab on the service, then the replacement widget opens its own anchored copy. | [SRC][INFER] |
| `shell.summon` chooses an already open bar widget first, otherwise the focused output. Restoring a destroyed popup through it can move Station to the primary/focused monitor. A `monitoradded` event handler also called `openPanel()` unconditionally, even when the user had closed the panel. The replacement widget now restores on the saved output, falls back if that output disappeared, and the event handler no longer summons a panel. | [SRC] |
| Disabling/enabling `omarchy.workspaces` changes the bar layout and recreates Station widgets. During that hand-off a transient close can clear both the reopen intent and remembered tab. Station now keeps the intent for a short transfer interval around the setting change and display preview; an explicit user close clears that interval. Repeated preview drags continue in the same 12-second confirmation session and retain the original Revert baseline. This repair is source- and isolated-test-verified; a physical monitor move under the new code remains to be checked. | [SRC][QTTEST] |
| A rebuilt Station panel previously initialized `selectedDisplayName` from the first draft display (`eDP-1` here). Selecting `HDMI-A-2` in a panel on that output then moving it rebuilt the panel and selected `eDP-1`; moving it from a panel on `eDP-1` concealed the reset because the fallback matched the selection. The selected connector now lives on the service and the inspector uses it again after a rebuild, falling back only while that connector is absent from the draft. | [LIVE][SRC] |
| The host `Ui.Dropdown` sizes its trigger and popup to the caller's `width`, with its chevron anchored at the trigger's right edge. Equal-width toolbar dropdowns therefore put excessive space between a short value and the arrow. The 2.0 render instead places compact Mode and Direction text menus in the top tab row; Station uses content-sized triggers and keeps Mode's popup wide enough for named Single-output choices, right-aligned so it stays inside the panel. | [SRC] |
| The stock Display panel's text-size control uses seven stops (`9, 10, 11, 12, 14, 16, 20` px) and runs `omarchy-display-text-size <px>`. That CLI changes the shell base font and GTK scaling; `Style.font.baseSize` follows via a file watch. Station reuses those stops and command, with a pending value while the style change is in flight. | [SRC] |
| `Ui.PanelSlider` supports integer-valued index sliders with visible `tickCount`, and emits `released` for both pointer release and mouse-wheel steps. Resolution and refresh bars can therefore index the display's exact allowlisted modes instead of interpolating unsupported values. The release handler previews only the final chosen mode. | [SRC] |
| The enlarged layout canvas supports a user zoom factor around the pointer and independent pan offsets. Isolated Qt pointer tests verify zoom preserves the targeted card point, background panning does not change display coordinates, and dragging a monitor still commits one preview. These are UI-transform tests only; no live compositor reconfiguration was exercised. | [QTTEST] |

### 8.6 Theme tokens (`import qs.Commons`, `import qs.Ui`)

| Group | Tokens that exist |
|---|---|
| Popups | `Color.popups.background`, `.text`, `.border` |
| Menus | `Color.menu.background`, `.text`, `.border`, `.scrim`, `.selectedBackground`, `.selectedText`, `.selectedBorder` |
| Global | `Color.foreground`, `Color.accent`, `Color.urgent` |
| Bar | `Color.bar.background`, `.text`, `.active` (**no** `Color.bar.foreground`). The injected widget-host `bar.foreground` is a separate API; fall back to `Color.bar.text`. |
| Geometry/type | `Style.cornerRadius`, `Style.space(px)`, `Style.spacing.*`, `Style.font.*`, `Border.surfaceSpec(...)`, `BorderSurface` |

Themes switch live: the shell updates the singletons and bindings repaint. Do not hard-code palette values; CI for Station fails on any hex colour (including short and alpha forms) and on symlinks. Do not copy Display's raw numeric spacing and font values.

### 8.7 Brightness

| Fact | Tag |
|---|---|
| Public CLI: `omarchy brightness display [--no-osd] [--monitor name] [+N%\|N%-\|N%\|off\|on]`. Write example: `omarchy brightness display --no-osd --monitor <name> 40%`. | [LIVE] |
| Read: `omarchy-brightness-display --monitor <name>` prints the percent on line 1; empty or `unavailable` means unavailable. Display's panel parses it with `parseInt`, clamps 0–100. | [SRC] |
| The binary routes internal panels to `brightnessctl`, ordinary external monitors to DDC/CI, supported Apple displays to an Apple helper. | [SRC] |
| **Never call `omarchy-brightness-display --help`:** the direct binary has no help handler and treats it as an adjustment argument. Use `omarchy brightness display --help`. | [LIVE] |
| Display's `Model.js` does not read brightness; it only clamps, labels and computes scale and parses display JSON. Reading goes Panel.qml → `omarchy-monitor-state` (every 5 s while open) → `omarchy-brightness-display --monitor <focused>`. | [SRC] |

### 8.8 FileView writes and reload validation

| Fact | Tag |
|---|---|
| `FileView.setText` with unchanged text does not provide a fresh `saved` acknowledgment. A recovered migration that rewrote an identical journal waited indefinitely. Incrementing a journal revision forces an acknowledged write for every attempt; wait for that acknowledgment before changing compositor state. | [LIVE][SRC] |
| Component compilation checks syntax/types but do not instantiate the service or exercise asynchronous file callbacks. Journal recovery needed a runtime test in addition to compilation. | [LIVE][SRC] |
| Plugin source reload alone did not reliably replace cached JavaScript during the compact-grid repair. Restarting the shell loaded the installed revision. Runtime binds are reinstalled asynchronously afterwards; an immediate count can temporarily be zero before returning to 36. | [LIVE] |

## 9. Station-specific design results that follow from the above

1. **Runtime effects are re-applied after every `configreloaded`** (binds, workspace rules, monitor runtime state), debounced ~300 ms.
2. **Unbind only what Station owns or was told to replace** (known Omarchy defaults, user-approved combos, combos it applied earlier); a blind unbind-before-bind can delete a user's own bind.
3. **File = geometry; runtime = mode.** `monitors.lua` carries a marked block with geometry and a fail-safe guarded disable; because the cold list is empty, the service applies mode after discovery.
4. **Preview/Keep transaction:** apply at runtime with a detached watchdog; on Keep: backup, atomic write, `hyprctl reload`, check `configerrors`, restore the backup on errors.
5. **Removal cleanup is a detached fixed-template script** with positional arguments only (never interpolated data).
6. **Grace delay 5 s** before merging windows after a removal; additions preserve windows' physical display and station while compact workspace IDs may change.
7. **Follow-focus must ignore workspace events during and shortly after topology changes.**

## 10. Security-relevant facts

- Monitor `description`, `make`, `model`, `serial` come from EDID and are untrusted: matching and display only, never interpolated into Lua, argv or file text without a proper serialiser. Connector names (`^[A-Za-z0-9_.:-]{1,64}$`) are kernel-generated and may be used once validated.
- Omarchy has itself shipped a fix for USB device names being executed as Hyprland Lua.
- `execDetached` and `Process` use argv arrays; shell templates take positional arguments only.
- The cleanup and Keep scripts refuse symlinked targets, write temp files then `mv`, and keep timestamped backups (last five).

## 11. Known traps (consolidated)

1. `hyprctl binds -j` cannot identify `code:` binds. Use `omarchy menu keybindings --print`.
2. Binding the same combo twice fires both. `hl.unbind` removes every entry on the combo, including the user's.
3. A reload erases runtime binds, workspace rules, and runtime monitor state.
4. Re-enabling `omarchy.workspaces` lands in `center` index 4; `bar put` will not fix it; use `bar move`.
5. `shell call` reaches panels only; use the service-owned `IpcHandler` target.
6. `Component.onDestruction` also fires on shell restart.
7. Cold-start `hl.get_monitors()` is empty during config evaluation.
8. `mirror` survives re-enable unless cleared with `mirror = ""`.
9. A spare workspace appears and disappears during an unplug; do not follow it.
10. On a fast reconnect Hyprland restores the workspace to the returning monitor by itself.
11. Synthetic keypresses do not exercise binds; use a real key press.
12. Popout content renders smaller than requested under theme scaling.
13. `omarchy-brightness-display --help` is not help.
14. `availableModes` has near-duplicates; the exact string matters.

## 12. Never tested (test before relying on)

- Three or four monitors (hardware was unavailable).
- Physical hotplug **during** a Station-generated eval, and two monitors added within a second (dock). See the review note in the project chat: the service's expected-event check must match output names.
- Dock behaviour with changing connector names across ports.
- Laptop lid close/open with an external monitor attached (clamshell), suspend/resume, and DPMS off/on cycles: these may emit monitor events and were not exercised.
- Fractional scaling and rotated monitors with the logical-coordinate canvas.
- HDR, VRR and colour management (out of scope).
- Behaviour on Hyprland main after 0.56.2 (bind reporting is expected to change).
- Role-swap scenarios and physical unplug/replug flows with many live windows (release-candidate manual tests).

## 13. Fingerprint and fast re-verification

If these all match, trust §2–§8 and skip the old tests. If any differs, re-verify only the sections it touches.

```sh
hyprctl version | head -3                 # expect 0.56.x, commit efb5099…
omarchy version                           # expect Omarchy 4
jq --version                              # expect jq-1.8.x
hyprctl eval 'return type(hl.get_monitors)' ; echo
omarchy-shell shell listPlugins | jq -r '.[0] | keys | join(",")'
omarchy menu keybindings --print | head -3
```

Five-minute smoke checks (each reversible): (1) `hyprctl eval` of one `o.bind` with a real keypress, then `hyprctl reload` and confirm it is gone; (2) a runtime `hl.workspace_rule` on a fresh workspace number; (3) `omarchy-shell <your-id> <method> <arg>` against a throwaway service; (4) enable/disable `omarchy.workspaces` and confirm the `center` fallback; (5) `hl.monitor` with an exact `availableModes` string.

## Preview restoration and shell reload observations (2026-10-05)

- Station suppresses `configreloaded` while applying a display layout. Therefore
  its own Revert must explicitly refresh the compositor snapshot, rebuild the
  display draft, and invalidate/reapply runtime bindings. Refreshing monitor data
  alone leaves the canvas and mode selector showing the discarded preview.
- A Quickshell SIGSEGV at 18:01:04 followed repeated local-plugin reloads and a
  restart request. The core stack includes `__dynamic_cast` and QML object
  finalization/incubation; it does not identify a Station QML callback as the
  cause. The shell automatically recovered. Omarchy's launch script separately
  documents restart crashes after reloading partially written trees. Updating
  the local checkout while the shell is stopped avoids that reload sequence;
  this is a precaution, not proof of the crash's root cause.

## 14. Display transaction repair (2026-10-08)

- **[SRC][QTTEST]** The monitor-card Off handler called `setDisplayValue()` and
  then `previewLayout()` on its own delegate. Publishing the new Repeater model
  destroys that delegate before the second call. The service now owns both steps
  in `setDisplayEnabled()`. The production QML handler is exercised by
  `tools/v2/check-layout.py`, including destruction during the Off action.
- **[SRC]** Preview migration was explicitly blocked by `reconcile()`. Single
  disabled the other output but did not compact/merge its stations until Keep.
  Preview now uses its own effective mode for journaled migration, retains a
  durable per-window baseline, and starts the countdown after migration. Revert
  and restart recovery restore the original station/output assignments.
- **[LIVE][SRC]** During the user's Keep attempts at 00:19:34, 00:20:01 and
  00:21:15 local, the Quickshell event log showed HDMI added/removed/re-added
  during reload. The saved monitor block contained Single on eDP-1, while
  Station's config and live mapping remained Extend. Hyprland `configerrors`
  was empty. `monitoradded` could call `updateAssignments()` while
  `applyingLayout`, reset the draft from old config, and reapply that old mode.
  Keep now captures accepted options and defers event-driven runtime changes
  until a fresh post-transaction snapshot. Candidate saves are acknowledged
  before launching the filesystem transaction.
- **[SRC]** The "Other monitor rules also mention" text was a nonfatal warning
  stored in the error field. Older geometry rules above Station's final managed
  block do not by themselves invalidate it. Keep no longer reports those
  mentions as an error or removes the user's earlier rules.
- **[SRC]** An existing widget on the surviving output was never told to reopen:
  restoration only ran on construction/service binding. The service now chooses
  a usable destination, and existing panels observe transfer/screen changes.
  A still-open copy on the output being disabled cannot block the hand-off.
- **Verification:** `test/v2/display-transaction.test.cjs` executes production
  service functions with queued compositor events and disk acknowledgments. It
  covers immediate migration, Keep reload races, repeated mode previews,
  timeout, Revert, restart recovery, enabling a Single-mode disabled output,
  and candidate-write failure. These tests do not simulate GPU/Wayland internals.
- **[LIVE] Installed repair `103a6de`:** a Single-on-eDP-1 preview moved all
  eight eligible windows to their compact single-display station IDs. A panel
  opened on HDMI-A-2 transferred to eDP-1; `hyprctl layers -j` confirmed the
  visible keyboard-panel surface there, with 12 seconds remaining. Revert
  restored every checked window's original workspace and physical monitor.
- **[LIVE] Keep:** repeating that Single preview and pressing Keep persisted
  `single`/`eDP-1`, retained the single-output map, and produced no layout error.
  The verification then saved Extend and restored original window ownership,
  monitor geometry, focus, and the initially closed panel state. This also
  repaired the earlier saved-block/config mismatch. A subsequent Mirror
  preview migrated all seven then-present eligible windows and passed Revert.
- **[LIVE] Final state:** idle, saved/draft mode Extend, two-output workspace
  map, no pending migration, empty layout error, and empty Hyprland
  `configerrors`. No crash or zero-output warning appeared during these checks.
  Temporary snapshots: `/tmp/station-display-live-FZjoI9` (Single/Revert),
  `/tmp/station-display-live-qozfEr` (Single/Keep/restoration), and
  `/tmp/station-display-live-rCG0QJ` (Mirror/Revert). These contain local window
  metadata and are not committed. The automated suite (16 test files), 16 Qt
  layout tests, and installed-component QML compilation also passed.

## 15. Where evidence lives

| Source | Content |
|---|---|
| `docs/v2/M0.md` | 13-item gate with observations |
| `docs/v2/M0-evidence.json` | source hashes, 20 latency samples, monitor snapshot |
| `docs/v2/COLD-LOGIN-CHECK.md` | cold-start procedure and result |
| `docs/TEST-RESULTS.md` | automated and live integration results |
| `docs/ARCHITECTURE.md` | how the service is structured |
| `tools/v2/probe-platform.mjs`, `live-m0.py`, `cold-login.py` | read-only probes and the live runner |
| `archive/dev-before-v2-20261004` | abandoned v1-era history; read-only reference, never merge |
