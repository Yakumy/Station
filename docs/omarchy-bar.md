<!-- summary: How Station's bar is compared with Omarchy's, how to close a gap, what Station adds, its own widgets. -->
<!-- code: lib/bars/omarchy/** Bar.qml test/lint/bar-upstream.py -->
# Omarchy's bar and Station's bar

Other plugins are written for Omarchy's bar and tested on it. Station's bar replaces it
([why](decisions.md#keep-the-adapted-bar-whole)), so a difference nobody chose is a bug
for those plugins. Station's bar is therefore **Omarchy's bar plus a written list of
differences**, and every commit and release checks that this is still true.

## What is compared

| File | Holds |
| --- | --- |
| `test/fixtures/omarchy-bar/Bar.qml`, `BarModel.js` | Omarchy's bar, exactly as Station's was last brought up to it |
| `test/fixtures/omarchy-bar/pin.json` | Which Omarchy commit that is, and older releases Station still supports |
| `test/fixtures/omarchy-bar/differences.json` | Every member of Omarchy's bar that Station changes or leaves out, under its reason |
| `lib/bars/omarchy/MonitorBar.qml`, `BarModel.js` | Station's bar. In `BarModel.js`, everything above "Station's additions" is Omarchy's, untouched. |

| Check | Fails when | Runs in |
| --- | --- | --- |
| `test/unit/bar-upstream.test.cjs` | Station's bar differs from the pin in a way that is not listed, or a listed difference is gone | `test/run.py`, CI |
| `test/lint/bar-upstream.py` | The installed Omarchy's bar is neither the pin nor an older reviewed release, or Omarchy's shell calls something `Bar.qml` does not have | `test/run.py` |
| `test/lint/bar-upstream.py --latest` | The same, against Omarchy's development branch | CI job `Omarchy bar gap`, and before a release |
| `test/qml/bar-drag.py` | Dragging, sections, the tray drawer, sides, styles, zoom, panels or reserved space misbehave on Station's real `Bar.qml` | `test/run.py qml` |

CI's `Omarchy bar gap` is not a required check. Omarchy can change at any moment, and that
must not block an unrelated fix. It still has to be closed before the next commit that
touches the bar, and before any release.

## Rules

1. **A bar test fails, or a user reports that something works on Omarchy's bar:** read how
   Omarchy's current bar does it first. If it differs from Station's, port Omarchy's
   version. Invent a fix only when Omarchy's bar has the same fault, or when the fault is
   in a listed difference.
2. **Every commit:** `test/run.py` must pass. It includes the parity test and the gap check
   against the installed Omarchy.
3. **Every release:** `test/lint/bar-upstream.py --latest` must also pass.
4. **A gap is found:** close it before anything else in that commit or release. Re-pinning
   without porting hides it, and the parity test then lists everything left to port.
5. **A new difference:** add it to `differences.json` with a reason a plugin author would
   accept. "Station did it this way before" is not one.

## Close a gap

1. Read what changed, and why. `git log` in an Omarchy checkout gives each change's reason:

   ```sh
   git -C <omarchy> fetch origin
   git -C <omarchy> log -p $(python3 -c "import json;print(json.load(open('test/fixtures/omarchy-bar/pin.json'))['commit'])")..HEAD -- shell/plugins/bar/Bar.qml shell/plugins/bar/BarModel.js
   ```

2. Re-pin to the checkout: `python3 test/lint/bar-upstream.py --pin <omarchy>`.
3. Merge Omarchy's change into Station's bar. Between the old pin and the new one, a
   three-way merge does most of it:

   ```sh
   git show HEAD:test/fixtures/omarchy-bar/Bar.qml > /tmp/base.qml
   git merge-file lib/bars/omarchy/MonitorBar.qml /tmp/base.qml test/fixtures/omarchy-bar/Bar.qml
   ```

   Copy `BarModel.js` above "Station's additions" as it is.
4. Run `node --test test/unit/bar-upstream.test.cjs`. It names each member still different.
5. Add a scenario to `test/fixtures/bar-drag/shell.qml` for changed behavior. Check that it
   fails on the old bar: `STATION_BAR_ENTRY=<old checkout>/Bar.qml python3 test/qml/bar-drag.py`.
6. Run `test/qml/bar-drag.py` against each Omarchy in `pin.json`'s `older` too, with
   `OMARCHY_PATH` set to an export of that release. Station supports both.
7. Update the documents, then run `python3 test/run.py all`.

## What Station adds

`differences.json` is the list. In short: one instance per monitor, with its own side,
height, width, content zoom, background and Pill style; one widget pool for both
orientations, so a side change keeps an open panel; panels aligned to the bar's edges;
a space between the monitor and a Pill, Solid or Blur bar;
Station's own logo and indicator, which are not saved in the layout; and no blur, shadow or mixed color
in the removal animation.

### Station's own widgets

Station's bar draws two of its own: the logo (`yakumy.station`), which opens the panel, and
the indicator (`yakumy.station.indicator`), which shows the numbers and open apps. On
Omarchy's bar they stay one widget, because a plugin has one there.

While Station is the bar, neither has a row in `shell.json`'s layout, so that disabling the
plugin unloads it. Their places are saved beside it:

```json
{ "stationWidget": { "section": "left", "index": 1 },
  "stationIndicator": { "section": "right", "index": 0 } }
```

An index counts the widgets that section draws, for the logo without the indicator and for
the indicator with the logo. A missing or malformed logo place means beside the Omarchy
menu, and a missing or malformed indicator place means just after the logo. An index past
the end means the end. Dragging another widget writes neither, so an unmoved logo follows
the menu and an unmoved indicator follows the logo. Dropping the indicator back beside the
logo removes its key. Neither can be pulled off the bar.

The indicator reads the service through the logo widget on the same bar
(`StationPanel.indicator`), so a bar runs one bridge poll. Without that widget it is hidden.

`BarModel.stationLayout` draws this layout and `BarModel.editStationLayout` writes a drag
back to it. Omarchy's migration of `bar.centerAnchor` skips replacement bars, so both split
the center section around it as that migration does. The first drag saves the result and
drops the key.
