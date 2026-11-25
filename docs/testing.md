<!-- summary: Run the checks, test layout, QML harnesses, CI, evidence tags, coverage gaps. -->
<!-- code: test/** -->
# Testing

Everything lives under `test/`, and `test/run.py` is the single entry point.

## Run the checks

```sh
python3 test/run.py        # portable: Node tests, theme tokens, Omarchy bar gap, documentation, whitespace
python3 test/run.py qml    # portable, then every QML harness
python3 test/run.py all    # qml, then the QML compile and plugin validation
```

Run `all` before a commit that changes runtime code. It needs a Wayland session. It
does not change monitors, Station's configuration or the installed plugin. `bar-drag`
starts a nested Hyprland silently on `special:station-test`, with its own runtime directory
and headless outputs, and removes it. It skips without a Hyprland session.

A harness that nothing runs goes stale. `test/run.py` discovers `test/qml/*.py` and
`test/unit/*.test.*` by file name, so a new file joins the run automatically.

## Layout

| Path | Runs on | What it proves | What it does not prove |
| --- | --- | --- | --- |
| `test/unit/` | Node, Lua and Perl | Policy, production function bodies, fixed shell programs with fake commands | QML signal order, rendering, hardware |
| `test/qml/` | Qt, offscreen or isolated Wayland | Production components with doubled effects, bindings, timers, pointer events | Physical input, compositor effects |
| `test/lint/` | Node, Python and Quickshell | Theme tokens, that all runtime QML compiles against the installed host, and that Omarchy's bar has not moved on | Runtime behavior |
| `docs/find.py --check` | Python | Document sizes, links and anchors, that a document covers every source file, current indexes | That a document is true |
| `test/live/` | The live session | M0 and cold-login platform experiments | Not routine. See [Live runners](#live-runners). |
| `test/helpers/`, `test/fixtures/` | | Shared test code and fixtures. `wayland.py` is the socket check of the rendered harnesses, `headless.py` the nested compositor. | |

Node tests extract production function bodies from QML and run them against a fake
namespace. `test/helpers/runtime-source.cjs` loads the owners and adapts their ports.
This design keeps scenarios readable, but it cannot prove QML binding behavior. The
QML harnesses cover that part.

## QML harnesses

| Harness | Exercises |
| --- | --- |
| `bar-icons`, `bar-rendering`, `open-apps` | Bar glyphs, content zoom, and the app drawer in each compact mode with apps on and off |
| `bar-settings`, `bar-tab` | Bar owner and tab, with fake effects |
| `bar-drag` | Station's real `Bar.qml` with the installed host's Ui and Commons, on two headless outputs: drags within and between sections, around and of Station's own logo and indicator, together and apart, into and out of the tray's drawer, after a hold, off the strip and off the bar; every edge, both styles, zoomed and not; the compositor's own pointer reaching each bar after every move between edges; Omarchy's own indicators showing under the pointer on every edge; the space each background keeps from the monitor; the bar dragged from every edge to every other; instances kept through drags and side changes; geometry, panels, an old `centerAnchor`, what Omarchy's shell calls, and the space each bar reserves. Drag events are Qt's and skip the compositor's input region, so a change to a region needs the pointer scenario. A cursor warp sends no motion within one surface. `STATION_BAR_ENTRY` runs it on another checkout's bar, `OMARCHY_PATH` on another host |
| `binding-picker` | Key capture |
| `display-owner`, `display-fileview` | Preview and Keep with fake effects, then real `FileView` objects on temporary files |
| `workspace-owner`, `workspace-fileview` | Journal with fake effects, then real `FileView` objects on temporary files |
| `layout` | Pointer events on the display layout |
| `panel-session`, `panel-composition`, `panel-size` | Panel lifetime, all eight tabs on both paths, fixed frame; closed Compact On indicator latency without full-snapshot reads; Bar portrait frames, centered drawers with the caption message under the buttons, Keep/Revert painted inside the viewport after a runtime landscape/portrait toggle, and right-aligned Keybindings combos |
| `color-match` | Color Match tab rendered with HDR and adjusted monitors, live values and release calls; the owner with a real `FileView`, a recording queue and a failed apply |
| `workspaces-tab` | Workspaces tab badges and roles in all three modes, − and + limits, Non-repetitive drop targets and moves, Cancel and Apply, and the disabled selector on one monitor, rendered |
| `wallpaper-layout` | Crop gestures |
| `wallpaper-tab` | Mode and Follow dropdown bindings, filename hints, per-monitor selection and native-menu requests, rendered with a fake owner |
| `window-settings`, `window-sliders`, `windows-tab` | Window owner, slider pointer events, preview exchange |

## Continuous integration

`.github/workflows/checks.yml` runs `Station portable checks`: `test/run.py` plus a
whitespace check of the commit. It runs on pushes and pull requests to `main` and
`dev` on a GitHub-hosted runner, with read-only permissions and no secrets. Do not run
contributor pull requests on a runner attached to your desktop.

Installed-host tests skip without Omarchy. Passing CI does not prove QML compilation,
rendering or monitor behavior, so run `test/run.py all` locally before a release.
GitHub requires this check on `main`. A second job, `Omarchy bar gap`, compares the pinned
bar with Omarchy's development branch. It is not required, but a failure must be closed
before a release ([Omarchy's bar](omarchy-bar.md#rules)).

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

## Coverage gaps

Hardware cases that have no recorded pass on the current code:

- H1 to H9 and H11 on the feature-folder layout. On 2026-11-05 the installed plugin
  passed an ordinary restart, panel open and close, station switching and return, and
  an unchanged-topology preview with Revert. Other evidence predates the move.
- Three and four outputs and docks. The maintainer has neither, so these stay unverified.
- A full reboot with the current DRM presence guard, suspend and DPMS.
- The direct path in a running shell. This machine runs the bridge path, and
  `panel-composition` covers the direct path in isolation.
