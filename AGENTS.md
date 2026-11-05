# Station development guide

Station is the `yakumy.station` Omarchy 4 plugin for Hyprland's Lua configuration. Read
this file before you change anything. [docs/README.md](docs/README.md) indexes the rest.

## Start here

| Task | Read first |
| --- | --- |
| Any change | [Architecture](docs/architecture.md) to find the owner |
| Behavior | [Contracts](docs/contracts.md) section for that feature |
| Platform behavior | [Platform findings](docs/platform-findings.md) §0, §11 and §13 |
| UI | [Design system](docs/design-system.md) |
| Videos, banners, screenshots, GIFs, themes | [Branding](docs/branding.md) |
| Install, publish, marketplace | [Releasing](docs/releasing.md) |
| A design choice you want to change | [Decisions](docs/decisions.md) |

## Commands

```sh
git status --short                 # before editing, to preserve work in progress
python3 test/run.py                # portable checks
python3 test/run.py qml            # portable checks and all QML harnesses
python3 test/run.py all            # everything: needs a Wayland session
node --test test/unit/grid.test.cjs     # one test file
python3 test/qml/panel-session.py       # one harness
omarchy-shell yakumy.station status     # running service state
```

`test/run.py all` changes no monitor, configuration or installed file. It passing does
not prove a live monitor transaction or final rendering. See [Testing](docs/testing.md).

## Boundaries

### Always

- Work on `dev`. Preserve existing work and desktop state.
- Find the owner in `lib/` and read its contract and tests before you change it.
- Run the focused tests, then `python3 test/run.py all`, before a commit that changes
  runtime code.
- Change documents in the same commit as the behavior.
- Report what you tested versus what you inferred. Use the evidence tags in
  [Testing](docs/testing.md#evidence-levels).
- Before a requested commit, inspect the complete diff, stage only the task's files and
  inspect the staged diff.
- Before a live experiment, inspect current state and take recoverable backups. Restore
  the original state afterward.

### Ask first

- Commit or amend, unless the user already authorized it for this task.
- Update the installed plugin. See [Releasing](docs/releasing.md).
- Run a topology change, crash, removal or physical-unplug experiment.
- Run anything under `test/live/`. These runners change the live session.
- Change a persisted format, or delete the plain geometry copy
  ([why](docs/decisions.md#keep-the-plain-geometry-copy)).

### Never

- Never push without explicit authorization. Never force push. Never push from the
  installed checkout.
- Never edit `/usr/share/omarchy`.
- Never interpolate device text into shell or Lua. Use argv arrays or fixed scripts with
  validated positional arguments. EDID-derived fields are untrusted.
- Never use a private palette, a hardcoded radius, a shadow, a glow or a gradient.
- Never claim that a simulator test proves a hardware path.
- Never repeat a `[LIVE]` experiment only to rediscover a documented result.

## Invariants that are easy to break

The [contracts](docs/contracts.md) are authoritative. These fail silently or damage a
session, so check them on every related change.

- **One service.** Children receive data and finite ports, never the Service object. Do
  not instantiate a second service.
- **Bridge identity.** Import `lib/BarBridge.js` only in the top-level `Panel.qml`,
  `Service.qml` and `Bar.qml`. Do not move it. A nested import creates a second library
  instance.
- **Bridge contract.** Change `lib/panel/ServiceContract.js`, the proxies and the bridge
  tests together. Expose detached data only, never a QObject. Deferred hand-off work
  captures the bridge API and scalars, never a proxy.
- **QML imports.** Give each feature folder its own qualifier. Sharing one breaks only
  under the real Quickshell loader, so `test/lint/compile-qml.py` is the check.
- **Journal first.** Wait for the save acknowledgment before moving windows. Keep the old
  map until verification and commit. Resume by window identity, never by decoding IDs.
  Identical `FileView.setText` text emits no acknowledgment.
- **Evacuation.** Never disable or mirror an output that owns an open keyboard-focused
  panel before the panel closes and acknowledges, and a survivor is enabled and focused.
  A panel on a surviving output stays open, after hiding its dismiss surface on the
  leaving output.
  Never leave zero real outputs.
- **Previews.** Keep the 20-second detached watchdog and the 12-second countdown. Keep the
  original baseline through re-edits.
- **File writes.** Change only marked sections at the beginning of `monitors.lua` and
  `looknfeel.lua`. Keep the source comparison, backup and conditional rollback.
- **Observation.** Never replay cached monitor or window settings. Explicit edits persist.
- **Reloads.** A successful watched apply must not force a second reload. Window sliders
  apply with no full reload and no fixed sleep, and restore autoreload on every exit.
- **Binds.** `hl.unbind` is sensitive to modifier order. Unbind only known Omarchy defaults,
  approved combos and Station's own applied combos. Use `omarchy menu keybindings --print` for identity. Only real key presses test
  the end-to-end path.
- **Workspace numbering.** Omarchy's per-monitor reconcile renumbers station workspaces,
  so `WorkspaceAuthority` must stay armed. See [Workspace authority](docs/contracts.md#workspace-authority).
- **Restart versus removal.** A shell restart must not trigger removal cleanup.
- **Delegates.** A Repeater delegate can be destroyed during its own handler. Keep
  follow-up actions in a surviving object.
- **Layout.** `Style.space()` scales with the theme. Compiling does not prove that a panel
  looks right.
