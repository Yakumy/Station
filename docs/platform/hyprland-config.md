<!-- summary: hyprctl eval and Lua config, reload effects, socket2 events, cold start, untrusted text, setting authority. -->
<!-- code: lib/platform/Hypr.js lib/platform/Events.js lib/platform/Compositor* Service.qml -->
# Hyprland configuration, events and startup

Dated sections are investigations, oldest first. A later one can supersede an earlier one.

## Hyprland Lua configuration and `hyprctl eval`

| Fact | Tag |
|---|---|
| Since 0.55 hyprlang is deprecated; configuration is Lua. Under a Lua config the legacy `hyprctl keyword` form is rejected; runtime changes go through `hyprctl eval '<lua>'`, which prints `ok` on success. | [DOC][LIVE] |
| After an ordinary manual Lua config change validate with `hyprctl reload` then `hyprctl configerrors` (empty output = clean). Station is a special case: its accepted preview is already live and saving the watched `monitors.lua` triggers autoreload, so Keep no longer forces a second reload. It waits 1 s and checks `configerrors`; an error restores the backup and forces that recovery reload. | [SRC] |
| One `eval` can contain many statements joined with `; `. Twelve `window.move` dispatches in a single eval, no sleeps, completed in about 10 ms including process and IPC overhead. | [LIVE] |
| Dispatch syntax that works (used by v1 for a month and by v2): `hl.dispatch(hl.dsp.window.move({ window = "address:0x…", workspace = N, follow = false }))`, `hl.dispatch(hl.dsp.workspace.move({ workspace = N, monitor = "NAME" }))`, `hl.dispatch(hl.dsp.dpms({ action = "off", monitor = "NAME" }))`. | [SRC][LIVE] |
| Focus constructors accepted and working: `hl.dsp.focus({ workspace = "N" })` and `hl.dsp.focus({ monitor = "NAME" })`. A two-monitor batch focused one workspace per monitor and then restored focus to the original monitor. | [LIVE] |
| The `hl` table can be enumerated with `pairs(hl)` from an eval (write results to a file with `io.open`). `hl.get_monitors` is present. | [LIVE] |
| `hl.get_monitors()` returns a Lua table of userdata (`HL.Monitor(<id>:<name>)`). Readable fields: `id`, `name`, `width`, `height`, `scale`, `active_workspace` (userdata `HL.Workspace`); position and size are tables; `enabled` is `nil`. It is **not** the JSON that `hyprctl` returns. | [LIVE] |
| Omarchy provides an `o` helper available inside `eval`: `o.bind(keys, description, action)` works there (see [Keybindings](keybindings.md)). Omarchy also has `o.window(match, rules)` for window rules (see `$OMARCHY_PATH/default/hypr/windows.lua`). Window-rule syntax changes between Hyprland versions: always read the current wiki before writing rules. | [LIVE][SRC] |
| Omarchy user config lives in `~/.config/hypr/` (`hyprland.lua`, `bindings.lua`, `monitors.lua`, `input.lua`, `looknfeel.lua`, `autostart.lua`). `omarchy refresh hyprland` resets them to defaults. Never edit `/usr/share/omarchy`. | [SRC] |
| Hyprland hot-reloads config on save. `hyprctl reload` forces it. **A reload clears all runtime state** ([binds](keybindings.md), [rules](workspaces.md), [monitors](monitors.md)). | [LIVE] |

## Events (Hyprland socket2 and Quickshell)

| Fact | Tag |
|---|---|
| Quickshell exposes socket2 as `Hyprland.rawEvent`; in QML: `Connections { target: Hyprland; function onRawEvent(event) { … event.name … } }`. Verified in the running v2 service. | [LIVE] |
| Event text forms seen: `monitorremoved>>NAME`, `monitorremovedv2>>ID,NAME,DESCRIPTION`, `monitoraddedv2>>ID,NAME,DESCRIPTION`, `moveworkspace>>WS,MONITOR`, `moveworkspacev2>>ID,WS,MONITOR`, `createworkspace>>N`, `workspace>>N`, `destroyworkspace>>N`, `focusedmon>>MONITOR,WS`, `configreloaded>>`, `closelayer>>omarchy-bar`. | [LIVE] |
| **Physical unplug, observed order** (60 s clean run; everything within about half a millisecond): `createworkspace>>3`, `workspace>>3`, `moveworkspace>>1,eDP-1`, `destroyworkspace>>3`, `monitorremoved>>HDMI-A-2`, `monitorremovedv2`. About 14 ms later `closelayer>>omarchy-background`, ~90 ms after that `closelayer>>omarchy-bar`. No `configreloaded`, no `monitoradded` during the 60 s. | [LIVE] |
| The spare workspace `3` is transient (created, focused, destroyed in the same millisecond) and absent from before and after snapshots. Follow-focus logic that reacts to `workspace>>` during a topology change will chase it. | [LIVE] |
| **Fast reconnect (3.7 s):** `monitoradded` came with Hyprland itself moving the workspace and its windows **back** to the returning monitor (`moveworkspace>>1,HDMI-A-2`). A merge before that point would have been undone. Hence the 5 s default grace delay. | [LIVE] |
| `hyprctl reload` emits one `configreloaded`. `omarchy theme set <name>` (even re-applying the same theme) emits **two**, about 220 ms apart. Use a trailing debounce of about 300 ms. | [LIVE] |
| Software disable emits focus and workspace migration then `monitorremoved`; enable emits `monitoradded`; mirror emits workspace events. A Station-generated eval therefore must record an "expected events" window **before** the eval. | [LIVE] |
| Unrelated physical hotplug happening while a Station-generated eval is in flight was **not** tested (see [Never tested](../platform-findings.md#never-tested-test-before-relying-on)). | — |

## Cold start and boot

| Fact | Tag |
|---|---|
| During `monitors.lua` evaluation at **cold compositor start**, `hl.get_monitors` exists but returns an **empty table** (two sessions: external connected; laptop-only). Monitors appear normally afterwards. | [LIVE] |
| Therefore a guarded block that disables monitors only when `up[name]` is true will emit **no** disable at login. It is fail-safe, but Single/Mirror mode cannot be enforced from the file at boot: the service applies saved mode once monitors are visible, so the first moments may be in Extend. | [LIVE] |
| On a warm `hyprctl reload`, `hl.get_monitors()` during parse **does** return the connected monitors. | [LIVE] |
| Hyprland starts the shell via autostart; the shell is supervised and returns after `SIGKILL`. | [LIVE] |

## Security-relevant facts

- Monitor `description`, `make`, `model`, `serial` come from EDID and are untrusted: matching and display only, never interpolated into Lua, argv or file text without a proper serialiser. Connector names (`^[A-Za-z0-9_.:-]{1,64}$`) are kernel-generated and may be used once validated.
- Omarchy has itself shipped a fix for USB device names being executed as Hyprland Lua.
- `execDetached` and `Process` use argv arrays; shell templates take positional arguments only.
- Process arguments are visible to other local accounts, so file text goes on stdin. [TESTED]
  on Quickshell 0.3.2: with `stdinEnabled` set before the start, `write()` in `onStarted`
  delivers the text as UTF-8, and `stdinEnabled = false` closes stdin, so `head -c` reads
  exact byte counts and later reads see end of input. A child that exits without
  reading stdin leaves the shell unharmed, and the next `Process` runs normally.
- The cleanup and Keep scripts refuse symlinked targets, write temp files then `mv`, and keep timestamped backups (last five).

## Station 3.0 system authority (2026-11-04)

- [SRC] Shared monitor and appearance preferences are no longer replayed by
  `applyRuntime`. Effective state updates the panel and workspace map. Personal
  bindings override automatic stock replacements; global blur remains external.
- [SRC] Persisted monitor and window-setting blocks precede personal rules.
  Compare-before-replace and conditional rollback preserve intervening edits.
- [SRC] Executed Node/Lua tests cover cold physical-presence guards, external
  topology adoption, numeric mirror IDs, and preview cancellation on reload.
- [SRC] This is a revision to the [design results](../platform-findings.md#design-results-that-follow), not a claim that
  Hyprland's documented reload behavior changed. See
  [the system authority contract](../contracts.md#system-authority). Cold login and physical hotplug under
  this version still require user verification.

Validation before installation: 226 Node tests, 23 offscreen layout cases,
theme-token checks, clean-copy plugin validation, live-backend component
compilation, and whitespace checks passed. The layout fixture retains its
known theme-double warnings. Hardware transition and visual acceptance remain
user tests; the automated checks do not establish those results.
