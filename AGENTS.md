# Station development guide

Read this before changing Station. This repository is the `yakumy.station`
Omarchy 4 plugin for Hyprland's Lua configuration. Work on `dev`; do not push.
Check `git status --short` before editing and
preserve work already in progress.

## Where to look

- [v2 build spec](docs/v2/SPEC.md): product behavior, invariants, security,
  transaction and removal contracts. Start with §§1–3, then the section for
  the feature being changed.
- [Platform findings](docs/PLATFORM-FINDINGS.md): observed Omarchy, Hyprland,
  Quickshell, and hardware behavior. Read §0 for evidence tags and §11 for
  known traps. Check §13's stack fingerprint before relying on old findings.
  Do not repeat a `[LIVE]` experiment just to rediscover a documented result.
  `[SRC]` is a source observation, `[QTTEST]` uses an isolated Qt harness,
  and `[INFER]` is not a confirmed hardware result.
- [Architecture](docs/ARCHITECTURE.md) and [README](README.md): current module
  map and user-visible workflow. [Design system](docs/v2/DESIGN-SYSTEM.md)
  governs UI work. [M0](docs/v2/M0.md) and
  [cold-login check](docs/v2/COLD-LOGIN-CHECK.md) are completed evidence, not
  routine tests.

Some examples and early plans in the spec predate later findings and repairs.
Use the verified findings and current implementation/tests for those details;
preserve the spec's behavioral and safety contracts. If a change invalidates a
documented fact or contract, update the relevant document in the same change.

## Repository shape and invariants

- `manifest.json` declares both a bar widget (`Panel.qml`) and a persistent
  service (`Service.qml`). The service owns IPC, Hyprland events, operation
  state, and panel hand-off intent; the UI does not own workspace policy.
- `lib/Grid.js` owns compact workspace numbering and migration plans;
  `Model.js` owns display identity, lanes, geometry, and mode choices;
  `Hypr.js`, `Binds.js`, and `MonitorsLua.js` validate and generate runtime
  commands/rules. `Store.js` handles versioned data. `Transactions.js` and
  `Recovery.js` contain fixed shell templates with positional arguments.
- A station has one workspace per active managed output:
  `(station - 1) * activeOutputCount + outputIndex + 1`. A saved output mapping
  decodes existing workspace IDs. Single and Mirror have one active output;
  at most three independent outputs are managed. Physical identity, preferred
  lane, current output slot, and displayed role are different concepts.
- Window migrations are journaled in `workspace-map.json`. Wait for the
  FileView save acknowledgment before moving windows; preserve the old mapping
  until verification and commit. Resume interrupted migrations by saved window
  identity and station, not by decoding partly migrated IDs. A preview keeps
  its original per-window baseline so Revert, timeout, and restart can restore
  it. `FileView.setText` with identical text emits no new save acknowledgment.
- Display topology edits use a preview, a detached 20-second watchdog, and a
  12-second Keep/Revert countdown. Never disable or mirror the output that owns
  an open keyboard-focused panel before closing/unmapping it, enabling and
  focusing a survivor, and receiving the panel acknowledgment. Never leave
  zero real outputs. Scale, Resolution, and Refresh are discrete side controls
  that save directly through the safe file transaction without a preview.
- Keep writes only Station's marked block at the end of
  `~/.config/hypr/monitors.lua`: backup, atomic replacement, watched Hyprland
  apply, `hyprctl configerrors`, rollback on failure. A successful watched
  apply must not also force a second reload or replay unchanged monitor rules.
  Recovery/rollback and removal still reload when required. `configreloaded`
  clears runtime binds and workspace rules; reapply them once per generation,
  with the existing debounce and expected-event handling.
- Only unbind known Omarchy defaults intentionally replaced, combos the user
  approved for replacement, or Station's own previously applied combos.
  `hl.unbind` removes every binding on a combo. Use
  `omarchy menu keybindings --print` for conflict identity; `hyprctl binds -j`
  cannot identify Lua `code:` keys. Real keys, not synthetic key events, verify
  the end-to-end bind path.
- `config.json` in `~/.config/omarchy/station/` holds preferences;
  `state.json`, `workspace-map.json`, and preview bookkeeping live under
  `~/.local/state/omarchy/station/`. On disable/remove, the detached cleanup
  distinguishes an enabled plugin after shell restart from an actual removal,
  restores only stock widgets Station leased, neutralizes Single/Mirror rules,
  and reloads Hyprland. A shell restart must not trigger removal cleanup.
- Validate connector names, exact allowlisted `availableModes` strings, Lua
  strings, IPC arguments, and paths before use. EDID-derived description and
  serial fields are untrusted. Use argv arrays or fixed scripts with validated
  positional arguments; do not interpolate device text into shell or Lua.

## UI and platform specifics

- Use installed `qs.Ui` components and `qs.Commons` tokens. Colors, corners,
  spacing, and typography come from `Color`, `Border`, and `Style`; no private
  palette, hardcoded radius, shadow, glow, or gradient. `Style.space()` scales
  with theme/font settings, so check actual layout geometry and text wrapping.
  Compile success alone does not prove a panel looks right or works live.
- The panel is a bar-widget popout. Bar/output rebuilds destroy its QML
  instance, so `Service.qml` retains open intent, selected monitor, and tab.
  Monitor cards are Repeater delegates: changing the model can destroy a
  delegate during its own handler. Keep follow-up actions in the service or
  another surviving object.
- Text size runs `omarchy-display-text-size` and changes shell, GTK, and
  terminal text globally. Per-monitor apparent size is the Scale control.
  Brightness reads and writes must carry the selected connector; unavailable
  notices belong to the matching control. Resolution/refresh selections keep
  an exact mode string from that monitor's supported list.
- Omarchy and Hyprland behavior is version-sensitive. Read packaged sources
  under `/usr/share/omarchy/` when needed, but never edit them. Cold
  `hl.get_monitors()` can be empty during `monitors.lua` evaluation; guard
  disabling rules and let the service apply saved mode after discovery.
  `mirror = ""` is needed to clear a previous mirror. Record expected monitor
  events before dispatch, and ignore transient workspace events during topology
  changes. Three/four-monitor hardware, simultaneous hotplug, and some
  Single/Mirror transitions remain unverified; do not claim a simulator test
  proves them on hardware.

## Development and verification

1. Identify the feature's owner in `lib/` or QML and read the matching spec,
   findings, and tests. Preserve existing desktop state; use isolated tests
   before live monitor actions. The M0 and cold-login runners modify the live
   session and are not routine checks.
2. Run the relevant focused tests, then the project's standard checks as
   appropriate to the change:

   ```sh
   node --test test/m0/*.test.mjs test/v2/*.test.cjs
   node tools/v2/check-theme-tokens.mjs
   python3 tools/v2/check-layout.py
   omarchy plugin validate .
   python3 tools/v2/check-qml.py .
   git diff --check
   ```

   `check-layout.py` is an offscreen pointer harness. `check-qml.py` needs the
   live Wayland backend and compiles components in a temporary Quickshell
   process without instantiating Station; running it in a sandbox without
   Wayland access can abort that test process. Neither check proves the live
   monitor transaction or final visual rendering.
3. For live work, inspect current monitor/config state and take recoverable
   backups before changing it. Keep the preview watchdog and rollback path
   intact. Record what was actually tested versus inferred; restore the
   original desktop state after an experiment.

## Installed plugin workflow on this machine

- The source checkout and `~/.config/omarchy/plugins/yakumy.station` are
  separate Git checkouts. Check both branches, status, revisions, and file
  hashes before saying an update is installed. The installed checkout's
  current origin is a local `file://` URL to this repository; verify that
  before using it. Keep both on `dev` and do not push.
- When the user asks for an installed update, finish and verify the source
  change first, commit if requested, then run
  `omarchy plugin update yakumy.station --yes` for a clean fast-forwardable
  installed checkout.
  Copying uncommitted files there makes it dirty and blocks that updater. An
  amended source commit is not fast-forwardable: inspect/clean only known
  agent-created edits, fetch the local `dev`, then move the clean installed
  `dev` checkout to that exact commit. Never discard unknown installed edits.
- A plugin rescan or file watch may leave an old Quickshell component cached.
  If the UI still shows old text/geometry, compare installed files to source,
  inspect the running shell's start time, then run `omarchy restart shell`
  once and verify `omarchy-shell shell ping`. Do not mistake an enabled
  `listPlugins` entry for proof that the running panel uses new code;
  `active: false` was observed even for enabled plugins.
