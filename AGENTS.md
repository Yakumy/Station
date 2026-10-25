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
  Do not repeat a `[LIVE]` experiment just to rediscover a documented result,
  unless a changed code path needs a regression check.
  `[SRC]` is a source observation, `[QTTEST]` uses an isolated Qt harness,
  and `[INFER]` is not a confirmed hardware result.
- [Architecture](docs/ARCHITECTURE.md) and [README](README.md): current module
  map and user-visible workflow. [Design system](docs/v2/DESIGN-SYSTEM.md)
  governs UI work. [M0](docs/v2/M0.md) and
  [cold-login check](docs/v2/COLD-LOGIN-CHECK.md) are completed evidence, not
  routine tests.

Some examples and early plans in the spec predate later findings and repairs.
The spec's behavioral and safety contracts remain authoritative. If a verified
later finding, the current implementation, or a test disagrees with the spec,
do not silently choose one: determine whether it is a documented revision or a
bug, then reconcile the affected documents in the same change.

## Repository shape and invariants

- `manifest.json` declares both a bar widget (`Panel.qml`) and a persistent
  service (`Service.qml`). The service owns IPC, Hyprland events, operation
  state, and panel hand-off intent; the UI does not own workspace policy.
- Replacement bars receive no live service. `lib/BarBridge.js` shares only
  detached `barSnapshot()` data and a closed action allowlist from the single
  persistent service; `BarServiceProxy.qml` and `WallpaperProxy.qml` implement
  the panel's surface. Keep the trusted built-in bar's direct lookup and disable
  bridge polling there. Import the bridge in top-level `Panel.qml` beside
  `Service.qml` and pass its reader to `StationPanel`: importing from the nested
  type produces a separate `qs:///` library under Quickshell. Extend the
  snapshot, allowlist, proxies, and bridge tests
  together when adding panel service members. Never expose WallpaperController
  (its `station` points back to the service), instantiate a second service, or
  capture a widget-owned proxy in deferred hand-off work: capture the bridge API
  and scalar values instead. Use setters for panel writes on both paths.
- Station 2.2 also declares a full-bar entry for per-monitor presence and
  position. `Bar.qml` hosts one isolated `lib/MonitorBar.qml` per connected
  Quickshell screen; the latter is an attributed Omarchy stock-bar adaptation.
  Keep the shared layout and host capability facade intact. When activating
  this bar, remove Station's persisted widget row atomically and let the bar
  inject its virtual Station slot, so plugin disable/remove unloads the service.
  Never edit `/usr/share/omarchy` to implement per-monitor behavior.
- `lib/Grid.js` owns compact workspace numbering and migration plans;
  `Model.js` owns display identity, lanes, geometry, and mode choices;
  `Hypr.js`, `Binds.js`, and `MonitorsLua.js` validate and generate runtime
  commands/rules. `Store.js` handles versioned data. `Transactions.js` and
  `Recovery.js` contain fixed shell templates with positional arguments.
- A station has one workspace per active managed output:
  `(station - 1) * activeOutputCount + outputIndex + 1`. A saved output mapping
  decodes existing workspace IDs. Single and Mirror have one station-bearing
  output (a mirrored sink may still be physically enabled); at most three
  independent outputs are managed. Physical identity, preferred lane, current
  output slot, and displayed role are different concepts.
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
- Keep changes only Station's marked block at the end of
  `~/.config/hypr/monitors.lua`, while the transaction atomically replaces the
  whole file: backup, marker-checked replacement, watched Hyprland apply,
  `hyprctl configerrors`, rollback on failure. A successful watched apply must
  not also force a second reload or replay unchanged monitor rules.
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
4. Before a requested commit, inspect the complete diff, stage only the files
   belonging to the task, and inspect the staged diff. Commit or amend only
   when the user requested it; never push.

## Installed plugin workflow on this machine

- The source checkout and `~/.config/omarchy/plugins/yakumy.station` are
  separate Git checkouts. Check both branches, status, revisions, and file
  hashes before saying an update is installed. The installed checkout's
  current origin is a local `file://` URL to this repository; verify that
  before using it. Keep both on `dev` and do not push.
- When the user asks for an installed update, finish and verify the source
  change first. The stock updater can install only committed source: it fetches
  the source checkout's current `HEAD` and runs `merge --ff-only`. If the user
  has not also authorized a commit, explain that requirement and ask rather
  than copying uncommitted files into the installed checkout. For an ordinary
  committed descendant, run
  `omarchy plugin update yakumy.station --yes`, then verify both revisions and
  statuses again. After **every** installed-plugin update, run
  `omarchy restart shell` once and verify `omarchy-shell shell ping`; do not
  rely on plugin file watches, a successful updater message, or matching file
  hashes as proof that the running shell loaded the new code.
- Never amend merely to make installation convenient. If the user explicitly
  requests both an amend and an installed update, the installed checkout's old
  commit will normally diverge and the stock updater will refuse it. Verify
  that the installed checkout is clean, still uses the expected local origin,
  and contains no unknown work; fetch that origin and obtain any approval
  required by the harness before moving **only the installed checkout's**
  `dev` branch to the exact fetched source commit. Never discard unknown edits,
  delete/reclone the checkout, or use a broad destructive command as a shortcut.
- A plugin rescan or file watch may leave an old Quickshell component cached.
  If the UI still shows old text/geometry after the mandatory restart, compare
  installed files to source and inspect the running shell's start time. Do not
  mistake an enabled `listPlugins` entry for proof that the running panel uses
  new code; `active: false` was observed even for enabled plugins.
