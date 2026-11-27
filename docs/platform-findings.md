<!-- summary: How Hyprland, Omarchy and Quickshell behave: evidence tags, tested versions, known traps, what was never tested. Index of the per-topic findings. -->
# Platform findings

This page records how Hyprland, Omarchy and Quickshell actually behave, so nobody re-runs an experiment to rediscover a result. Read only the topic you need. Dated sections record investigations in order. A finding can describe code that has since changed, so check [Contracts](contracts.md) for required behavior and [Architecture](architecture.md) for current file paths.

## Find the finding

<!-- index platform -->
| Read | For | Tokens |
| --- | --- | --- |
| [Bar blur and thickness](platform/bar-blur.md) | Layer-rule blur with global blur off, pass count, measured thickness against the stock bar. | 600 |
| [Hosting plugin widgets on a replacement bar](platform/bar-hosting.md) | What the host gives plugin widgets: bar api, tray sizing, service lookup, clipping and hover, panel hotkeys. | 1600 |
| [Bar geometry, dragging and position](platform/bar-layout.md) | Reserved space, spacing, edges, host sections, widget dragging, positions reverting, on/off stutter. | 3100 |
| [Bar text, image and logo rendering](platform/bar-rendering.md) | Content zoom, blurry text and images, the Station mark's tint, size and alignment. | 3000 |
| [Color Match ICC behavior](platform/color-match.md) | How Hyprland applies an ICC profile, what is ignored, how to clear one. | 800 |
| [Rotation, scale, snapping and the Off flag](platform/display-changes.md) | Investigations of rotation and scale geometry, edge snapping, the internal-monitor Off flag, Omarchy's own display panel. | 1900 |
| [Display preview and Keep investigations](platform/display-transactions.md) | Crashes and repairs in preview, Keep, reload-safe persistence and cold-start geometry. | 2700 |
| [Hyprland configuration, events and startup](platform/hyprland-config.md) | hyprctl eval and Lua config, reload effects, socket2 events, cold start, untrusted text, setting authority. | 2100 |
| [Station indicator and app icons](platform/indicator.md) | Open-app feed, icon sources and focus styling, indicator latency and live workspace. | 1600 |
| [Keybinding behavior](platform/keybindings.md) | How Hyprland and Omarchy report, register and remove binds, code: keys, modifier order. | 1100 |
| [Monitor behavior](platform/monitors.md) | hl.monitor rules, modes, mirror, disable, availableModes, stale outputs, ten-bit, crashes seen while switching. | 1800 |
| [Panel across bar rebuilds](platform/panel-rebuilds.md) | Why an open panel closed or jumped to another output when the bar or a stock widget changed. | 1400 |
| [Panel popout, canvas and controls](platform/panel.md) | KeyboardPanel structure and sizing, pointer input on the layout canvas, host dropdown and slider behavior, brightness and text size commands. | 2500 |
| [Omarchy shell and plugin system](platform/shell-plugins.md) | Plugin lifecycle, IPC, bar placement, enable and disable, destruction and removal, FileView writes, loader traps, installed smoke checks. | 2500 |
| [Theme tokens in qs.Commons and qs.Ui](platform/theme.md) | Which Color, Style and Border tokens exist, live theme switching, the Qt 6.12 Color singleton. | 700 |
| [Wallpaper and themes](platform/wallpaper.md) | Background layers, choosers, Screen remap crash, image decoding limits, theme and background change signals, theme switching. | 2100 |
| [Window settings](platform/windows.md) | Gaps, split, rounding and animation through hl.config, direct persistence, the Windows preview. | 2100 |
| [Workspace behavior](platform/workspaces.md) | Workspace rules, moves, renumbering by Omarchy, reconnects, scratchpads, four outputs. | 2500 |
<!-- /index -->

## How to use this document

- **Trust level.** Every entry carries a tag:
  - **[LIVE]** observed on a running system (Codex test sessions, 2026-10-04/05/08).
  - **[SRC]** read from installed Omarchy/Quickshell source or from Station v1/v2 code that ran on a real machine.
  - **[DOC]** stated in the official Hyprland wiki (Hyprland 0.55/0.56 Lua pages).
  - **[INFER]** reasoned from the above, not tested.
  - **[QTTEST]** production QML exercised with Qt pointer events in an isolated offscreen harness; theme painting and compositor calls are doubled. This is not a physical desktop test.
- **Do not re-run** anything tagged [LIVE] unless the [fingerprint](#fingerprint-and-fast-re-verification) shows the stack changed.
- **Do test** the items in [Never tested](#never-tested-test-before-relying-on).
- Provenance: round 1 results reached the author as a summary; rounds 2 and M0 and the cold-login and integration results as detailed reports. Raw captures lived under `/tmp/station-desktop-tests-20261004*` and `~/.local/state/omarchy/station-m0-cold/` on the author's machine and may no longer exist. These pages are the durable record. Monitor serial numbers are deliberately omitted.

## Environment tested

| Item | Value |
|---|---|
| Hyprland | 0.56.2 (`efb50993780079460b0cbed1363e2166a2de1d9f`), Lua configuration |
| Omarchy | 4 (branch "Quattro"), installed under `/usr/share/omarchy`, `$OMARCHY_PATH` set |
| Shell | `omarchy-shell` (Quickshell), supervised: it restarts itself after being killed |
| Tools | `jq-1.8.2` installed; `hyprctl`, `omarchy`, `omarchy-shell`, `omarchy-brightness-display` on PATH |
| Hardware | Two monitors only: a laptop panel (`eDP-1`) and one external HDMI monitor (`HDMI-A-2`). **Three- and four-monitor behaviour was never observed.** |
| Theme | Tokyo Night was the active theme (the theme-set test simply re-applied it) |

## Design results that follow

1. **Runtime effects are re-applied after every `configreloaded`** (binds, workspace rules, monitor runtime state), debounced ~300 ms.
2. **Unbind only what Station owns or was told to replace** (known Omarchy defaults, user-approved combos, combos it applied earlier); a blind unbind-before-bind can delete a user's own bind.
3. **File = geometry; runtime = mode.** `monitors.lua` carries a marked block with geometry and a fail-safe guarded disable; because the cold list is empty, the service applies mode after discovery.
4. **Preview/Keep transaction:** apply topology changes at runtime with a detached watchdog; on Keep: backup, atomic write, allow Hyprland's file-watch reload to settle, check `configerrors`, restore the backup and force a recovery reload on errors. Scale/Resolution/Refresh skip the runtime preview and use the same safe file transaction directly. Do not force a second successful reload after either path.
5. **Removal cleanup is a detached fixed-template script** with positional arguments only (never interpolated data).
6. **Grace delay 5 s** before merging windows after a removal; additions preserve windows' physical display and station while compact workspace IDs may change.
7. **Follow-focus must ignore workspace events during and shortly after topology changes.**

## Known traps (consolidated)

- **[SRC] Clipboard reads from hidden editors:** Qt 6.12.0's
  `QQuickTextInputPrivate::init()` connects clipboard `dataChanged` to
  `q_canPasteChanged()`, which retrieves text for writable inputs without a
  visibility/focus check. Wayland `QWaylandMimeData::readData()` appends data
  without a total byte cap and creates a fresh one-second deadline each loop.
  Sources: qtdeclarative `src/quick/items/qquicktextinput.cpp` and qtbase
  `src/plugins/platforms/wayland/qwaylanddataoffer.cpp`, tag `v6.12.0`.
  Hiding a native editor or limiting accepted text length does not bound that
  transfer. Station now uses `BindingKeyPicker.qml` without editable inputs.
  The local test stack is Qt 6.11.2; no hostile provider experiment has been
  performed against the reviewer's Arch Qt 6.12.0 package.

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
15. Never remove the output that owns an open keyboard-focused layer surface. Close and unmap it, enable/focus the survivor, then disable or mirror the old output; reopen only after compositor acknowledgement.

## Never tested (test before relying on)

- Three or four monitors (hardware was unavailable).
- Physical hotplug **during** a Station-generated eval, and two monitors added within a second (dock). See the review note in the project chat: the service's expected-event check must match output names.
- Dock behaviour with changing connector names across ports.
- Laptop lid close/open with an external monitor attached (clamshell), suspend/resume, and DPMS off/on cycles: these may emit monitor events and were not exercised.
- Fractional scaling and rotated monitors with the logical-coordinate canvas.
- HDR, VRR and colour management (out of scope).
- Behaviour on Hyprland main after 0.56.2 (bind reporting is expected to change).
- Role-swap scenarios and physical unplug/replug flows with many live windows (release-candidate manual tests).

## Fingerprint and fast re-verification

If these all match, trust the topic pages and skip the old tests. If any differs, re-verify only the sections it touches.

```sh
hyprctl version | head -3                 # expect 0.56.x, commit efb5099…
omarchy version                           # expect Omarchy 4
jq --version                              # expect jq-1.8.x
hyprctl eval 'return type(hl.get_monitors)' ; echo
omarchy-shell shell listPlugins | jq -r '.[0] | keys | join(",")'
omarchy menu keybindings --print | head -3
```

Five-minute smoke checks (each reversible): (1) `hyprctl eval` of one `o.bind` with a real keypress, then `hyprctl reload` and confirm it is gone; (2) a runtime `hl.workspace_rule` on a fresh workspace number; (3) `omarchy-shell <your-id> <method> <arg>` against a throwaway service; (4) enable/disable `omarchy.workspaces` and confirm the `center` fallback; (5) `hl.monitor` with an exact `availableModes` string.

## Where evidence lives

| Source | Content |
| --- | --- |
| `git show 0671e58:docs/v2/M0.md` | 13-item platform gate with observations |
| `git show 0671e58:docs/v2/M0-evidence.json` | Source hashes, 20 latency samples, monitor snapshot |
| `git show 0671e58:docs/v2/COLD-LOGIN-CHECK.md` | Cold-start procedure and result |
| `git show 0671e58:docs/TEST-RESULTS.md` | Automated and live integration results up to 2026-11-04 |
| `test/live/` | The read-only probe and the live runners |
| `archive/dev-before-v2-20261004` | Abandoned v1-era history. Read-only reference, never merge. |
