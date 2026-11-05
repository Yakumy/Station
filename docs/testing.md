# Testing

Everything lives under `test/`, and `test/run.py` is the single entry point.

## Run the checks

```sh
python3 test/run.py        # portable: Node tests, theme tokens, whitespace
python3 test/run.py qml    # portable, then every QML harness
python3 test/run.py all    # qml, then the QML compile and plugin validation
```

Run `all` before a commit that changes runtime code. It needs a Wayland session. It
does not change monitors, Station's configuration or the installed plugin.

A harness that nothing runs goes stale. `test/run.py` discovers `test/qml/*.py` and
`test/unit/*.test.*` by file name, so a new file joins the run automatically.

## Layout

| Path | Runs on | What it proves | What it does not prove |
| --- | --- | --- | --- |
| `test/unit/` | Node, Lua and Perl | Policy, production function bodies, fixed shell programs with fake commands | QML signal order, rendering, hardware |
| `test/qml/` | Qt, offscreen or isolated Wayland | Production components with doubled effects, bindings, timers, pointer events | Physical input, compositor effects |
| `test/lint/` | Node and Quickshell | Theme tokens, and that all runtime QML compiles against the installed host | Runtime behavior |
| `test/live/` | The live session | M0 and cold-login platform experiments | Not routine. See [Live runners](#live-runners). |
| `test/helpers/`, `test/fixtures/` | | Shared test code and fixtures | |

Node tests extract production function bodies from QML and run them against a fake
namespace. `test/helpers/runtime-source.cjs` loads the owners and adapts their ports.
This design keeps scenarios readable, but it cannot prove QML binding behavior. The
QML harnesses cover that part.

## QML harnesses

| Harness | Exercises |
| --- | --- |
| `bar-icons`, `bar-rendering`, `open-apps` | Bar glyphs, content zoom and the app drawer |
| `bar-settings`, `bar-tab` | Bar owner and tab, with fake effects |
| `binding-picker` | Key capture |
| `display-owner`, `display-fileview` | Preview and Keep with fake effects, then real `FileView` objects on temporary files |
| `workspace-owner`, `workspace-fileview` | Journal with fake effects, then real `FileView` objects on temporary files |
| `layout` | Pointer events on the display layout |
| `panel-session`, `panel-composition`, `panel-size` | Panel lifetime, all six tabs on both paths, fixed frame |
| `wallpaper-layout` | Crop gestures |
| `window-settings`, `window-sliders`, `windows-tab` | Window owner, slider pointer events, preview exchange |

## Continuous integration

`.github/workflows/checks.yml` runs `Station portable checks`: `test/run.py` plus a
whitespace check of the commit. It runs on pushes and pull requests to `main` and
`dev` on a GitHub-hosted runner, with read-only permissions and no secrets. Do not run
contributor pull requests on a runner attached to your desktop.

Installed-host tests skip without Omarchy. Passing CI does not prove QML compilation,
rendering or monitor behavior, so run `test/run.py all` locally before a release.
GitHub requires this check on `main`.

## Evidence levels

Report what ran, and do not promote a result to a stronger level.

| Tag | Meaning |
| --- | --- |
| `[LIVE]` | Observed on a running desktop |
| `[QTTEST]` | Production QML in an isolated Qt harness with doubled effects |
| `[SRC]` | Read from installed source |
| `[INFER]` | Reasoned, not observed |

An isolated test never proves a hardware path. Three- and four-monitor hardware,
simultaneous hotplug, lid and suspend paths, and cold login with the current block are
unverified (see [Coverage gaps](#coverage-gaps)).

## Live runners

**Warning: these runners change the live session.** Run them only for a changed
platform assumption, and never as a routine check.

- `test/live/live-m0.py` installs a fixture plugin and exercises platform behavior.
- `test/live/cold-login.py` adds a temporary probe to `monitors.lua`.
- `test/live/probe-platform.mjs` is read-only.

## Qualify a change on real hardware

Use this procedure when a change touches displays, migrations, evacuation or removal.

### Prepare

1. Get explicit permission for the specific cases. Crash, removal and physical unplug
   cases each need their own permission.
2. Make sure an operator can recover through a TTY. Use disposable test windows.
3. Record the source and installed revisions, the stack versions, and the connector
   names, modes, scales and rotations.
4. Back up `monitors.lua`, `looknfeel.lua`, Station's files, the Omarchy shell config
   and the internal-monitor toggle. Record hashes, `misc:disable_autoreload` and
   `hyprctl configerrors`. Keep EDID text and window titles out of public results.
5. Open identifiable windows on stations 1, 2 and 4 of each output, plus one floating
   window. Record each address, PID, class, station and output from the initial map.

### Capture

Capture these before the action, after it settles, and after you restore the setup.
"Settled" means that the operation and journal commit finished. A fixed sleep is not
a substitute.

```sh
hyprctl monitors all -j
hyprctl clients -j
hyprctl workspaces -j
hyprctl activewindow -j
hyprctl configerrors
hyprctl getoption misc:disable_autoreload -j
omarchy-shell yakumy.station status
```

### Cases

Run each mode case in both output directions and on both panel paths. Record pass,
fail or not run. Missing hardware means not run, never an inferred pass.

| ID | Steps | Pass condition |
| --- | --- | --- |
| H1 | In Extend, change the arrangement. Keep it. Repeat with Revert, then with the timeout. | Keep persists only the marked block and survives reload. Revert and timeout restore the topology and each window's station and output. Personal Lua is intact. |
| H2 | Open the panel on B. Choose Single A and Keep. Return to Extend. Repeat in the other direction, then with Revert and timeout. | A real output remains at every step. Windows keep their stations. Revert restores original outputs. |
| H3 | Mirror with A as source, Keep, return to Extend. Repeat with B. Swap the source, then go from Mirror to Single with the panel on the endangered output. | Only the source owns a station column. `mirror = ""` clears the mirror on return. Destinations match the plan. |
| H4 | Try to disable every output. Change scale, resolution and refresh one at a time. | The last real output stays on. Side controls save directly with no countdown. Exact modes apply. |
| H5 | Repeat H2 and H3, and record the serial, acknowledgment and focus order. Repeat with the panel on the survivor. | The acknowledgment follows unmap. Survivor focus precedes destructive rules. One panel reopens on the survivor. No crash. |
| H6 | Unplug B past the grace delay and reconnect it. Separately, reconnect inside the grace delay. | Stations survive. A returning output does not pull merged windows back. A fast reconnect cancels compaction. |
| H7 | During a preview, edit twice and add a window, then Revert. Repeat with an unplug and with an external reload. | The baseline survives re-edits. External changes cancel the preview and adopt the result. No window is lost. |
| H8 | With Omarchy's internal Off flag set, turn the output on. Revert, then time out, then Keep. Reload. | Only On + Keep clears the exact flag. Autoreload returns to its old value. Config errors stay empty. |
| H9 | With separate permission, kill the shell process during a preview. | The watchdog reloads current configuration. The new service resumes the journal with no duplicate binds. |
| H10 | Restart the shell once. With separate permission, disable the plugin, then remove and reinstall it. | A restart causes no cleanup and opens no panel. Removal restores only leased widgets, neutralizes rules and keeps preferences. Real number keys work. |
| H11 | With hardware, repeat H1 to H7 on three outputs and attach a fourth. Test dock, lid, suspend and cold login separately. | Three outputs keep station identity. The fourth stays untouched. Record actual behavior. |

Compute each expected destination from the committed map:
`(recordedStation - 1) * outputCount + outputIndex + 1`. Exclude pinned, special and
unmanaged windows.

Test rejected applies, source conflicts and stale acknowledgments in isolation first.
Do not corrupt real Lua or force zero outputs to create a failure.

### Restore

After each case, restore outputs, station, bar host, widgets, the toggle and autoreload.
Restore file bytes only where the current files are still this run's candidates.
Otherwise keep the newer edits and report the conflict. Never restore a stale journal
over live windows. If recovery fails, stop and preserve the evidence.

## Coverage gaps

Hardware cases that have no recorded pass on the current code:

- H1 to H9 and H11 on the feature-folder layout. On 2026-11-05 the installed plugin
  passed an ordinary restart, panel open and close, station switching and return, and
  an unchanged-topology preview with Revert. Other evidence predates the move.
- Physical key presses on the current layout.
- Three and four outputs, dock attach and detach, lid, suspend and DPMS.
- Cold login with the current DRM presence guard.
- The direct path in a running shell. This machine runs the bridge path, and
  `panel-composition` covers the direct path in isolation.
