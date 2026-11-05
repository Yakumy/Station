<div align="center">
  <img src="assets/station-main-logo.svg" alt="Station" width="112">
  <h1>Every display. One flow.</h1>
  <p><strong>Synchronized workspaces, display layouts, per-monitor bars, and wallpapers for Omarchy.</strong></p>
  <p>Keep your work together. Make each screen your own.</p>
  <p>
    <a href="https://omarchy.org"><img src="https://img.shields.io/badge/Omarchy-4%20Quattro-A6B465?style=flat-square" alt="Omarchy 4 Quattro"></a>
    <a href="manifest.json"><img src="https://img.shields.io/badge/Station-3.0.0-A6B465?style=flat-square" alt="Station 3.0.0"></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/License-Apache%202.0-A6B465?style=flat-square" alt="Apache 2.0 license"></a>
  </p>
  <p>
    <a href="#install">Install</a> ·
    <a href="#stations">Stations</a> ·
    <a href="#displays">Displays</a> ·
    <a href="#bars">Bars</a> ·
    <a href="#windows">Windows</a> ·
    <a href="#wallpapers">Wallpapers</a> ·
    <a href="#keybindings">Keybindings</a>
  </p>
</div>

![Animated illustration of switching all displays between stations](docs/assets/tours/stations.gif)

*One shortcut switches the whole setup. This is an illustrated tour. The panel previews below show the current UI.*

## Meet Station

A **station** is one workspace on each active display. Switch stations and every
screen follows. Send a window to another station and it stays on the same
physical monitor.

With two displays, S1 contains workspaces 1 and 2, and S2 contains 3 and 4.
Station manages that numbering for you, including when a display disconnects.

| Your workflow | What Station adds |
| --- | --- |
| **Move between projects** | Synchronized stations, directional navigation, and window moves with or without following. |
| **Change your setup** | A visual display editor with snapping, rotation, Extend/Mirror/Single modes, and guarded previews. |
| **Make room on every screen** | Independent bar placement, visibility, size, background, and Pill style. |
| **Frame your desktop** | The same wallpaper everywhere, one image per monitor, or a single image spanning the layout. |
| **Keep Omarchy familiar** | Native theme styling, familiar shortcuts, monitor-aware bar-position controls, and drag-to-position. |

## Your settings stay yours

Station follows what Hyprland and Omarchy actually apply. If you change a display or a
gap somewhere else, the panel updates. A reload never forces Station's saved values back
onto your system, and a temporary terminal change stays temporary.

When you edit a setting in the panel, Station saves only that setting, in a marked
section at the beginning of `monitors.lua` or `looknfeel.lua`, with a backup. Your own
rules later in the file still win on the next reload. See
[system authority](docs/contracts.md#system-authority) for the details.

## Install

Requires **Omarchy 4 (Quattro)** and **Hyprland 0.56+ with Lua configuration**.
Station manages up to three independent displays.

```bash
omarchy plugin add https://github.com/Yakumy/Station.git --enable
```

Click the Station logo in the bar to open the panel. Station discovers your
displays and enables its workspace shortcuts automatically. No initialization
command or additional dependencies are needed on a standard Omarchy install.

> [!TIP]
> Start with **Displays** to arrange your screens, then visit **Bar** and
> **Wallpaper** to customize the setup. **Keybindings** and **Settings** let you
> adjust how Station fits your workflow.

## Stations

**Keep a whole project one shortcut away.** Use `SUPER + 1…0` to switch every
active display together. The bar’s S1, S2, … indicator shows where you are.

- Move a window to another station and follow it, or send it silently while you keep working.
- Move directionally within a screen, across neighboring displays, and into the next station at the outer edge.
- Choose a station direction that matches your physical layout.
- Disconnect a display without losing each window’s station identity. Station compacts the workspace mapping and expands it when displays return.

The first display retains its role independently of the order in which outputs
are discovered. Station keeps physical identity, display roles, and workspace
numbers separate so changing a layout does not change what a station means.

## Displays

![Station Displays tab with a visual monitor arrangement and display controls](docs/assets/station-display.png)

**Arrange your screens where they actually sit.** Drag monitor cards, snap
shared edges, rotate a screen, and choose **Extend**, **Mirror**, or **Single**.
Unequal-height screens can slide along their shared edge instead of being forced
into corner alignment.

Select a monitor to control brightness, scale, resolution, and refresh rate.
Available modes come from that monitor. The text-size control changes text
across Omarchy. Display scale changes the apparent size on the selected screen.

Topology edits offer a **12-second Keep/Revert preview**, backed by an independent
20-second recovery watchdog. Station keeps at least one real output enabled and
moves its open panel to a surviving screen when needed. Scale, resolution, and
refresh changes save directly through the checked configuration transaction.
If you disabled the laptop display with `omarchy-hyprland-monitor-internal off`,
Station follows that state. Turning it On in Station and pressing **Keep** clears
Omarchy's Off toggle and saves your new layout. Revert leaves the toggle intact.

> [!NOTE]
> Station manages at most three independent outputs. Station reports additional
> outputs as unmanaged. Three- and four-monitor hardware transitions remain
> unverified on the current two-monitor test setup.

## Bars

![Current Station Bar tab showing independent monitor edges, content size, height, width, background, and style](docs/assets/tours/bars.gif)

*Rendered from the current Bar tab with isolated preview data. This animation changed no desktop settings.*

**A different bar for each display, with Omarchy’s controls still available.**
Select a monitor in the **Bar** tab and adjust:

| Control | What it does |
| --- | --- |
| **Presence and position** | Show or hide the bar on a display. Choose top, bottom, left, or right with the monitor-card arrows. At least one active display keeps a bar. |
| **Content size** | Enlarge icons and labels together. The live limit reserves padding and prevents the widget groups from overlapping. |
| **Height** | Change bar thickness, up to 5% of the monitor mode’s shorter dimension, subject to Omarchy’s readable minimum. |
| **Width** | Choose how much of the edge the bar occupies. Station keeps enough room for the widgets. |
| **Background** | Choose Solid color, Transparent, or Blur. |
| **Style** | Keep Omarchy’s default bar or use separate Pill groups. The tray pill expands as its drawer opens. |

Drag a bar’s free area toward a screen edge to move **only that monitor’s bar**.
Omarchy’s **Bar → Position** menu from `SUPER + Space` changes the bar on the
**focused monitor**. Station’s monitor-card arrows also control one monitor at
a time. The other displays keep their positions.

The bar keeps Omarchy’s widgets, shared widget layout, and theme colors.
Station’s logo renders as a vector so it stays sharp as content size changes.

**Open apps on the bar.** Settings offers Open on hover (the default), Always open, and
Hide. Click a station label or an app icon to switch to that station. Icons keep their
original colors at full opacity.

## Windows

**Tune window spacing and motion, and see the result before you release the slider.**
The **Windows** tab shows sample windows on your monitor layout and controls global
inner and outer gaps, the next Dwindle split, corner rounding, and animation speed.

Drag to preview, then release to apply and save. Changing speed plays one window moving
to the next monitor and another coming back. Speed 0 disables animations. Rounding also
changes Omarchy's shell corners, because both follow the same Hyprland setting.

## Wallpapers

![Animated illustration of wallpaper modes and framing one image across several monitors](docs/assets/tours/wallpaper.gif)

*Illustrated wallpaper tour. The screenshot below shows the real layout editor.*

![Station wallpaper editor framing an image across the physical monitor layout](docs/assets/station-wallpaper-real-layout.png)

**One image across your whole setup—or a different view on every screen.**

| Mode | Use it for |
| --- | --- |
| **Same on all** | Omarchy’s wallpaper or one local image on every display. |
| **Per monitor** | A different local image for each active display. |
| **Span** | One large image across the complete monitor layout. Drag the fixed monitor group to frame it and scroll to zoom. |

Span respects monitor positions, gaps, rotation, logical sizes, and scale. A
recommended source resolution helps you choose an image. Smaller images are
still allowed.

**Follow Omarchy wallpaper** is on by default, so theme and background changes
flow through automatically. Turn it off to keep your own images. Station
remembers image choices and Span framing per Omarchy theme/background pair.

Chosen images are prepared as private Station copies. Your originals and
Omarchy’s wallpaper links, theme files, and background history stay intact.

## Keybindings

| Action | Default shortcut |
| --- | --- |
| Switch station | `SUPER + 1…0` |
| Move window to station and follow | `SUPER + SHIFT + 1…0` |
| Send window without following | `SUPER + SHIFT + ALT + 1…0` |
| Previous / next existing station | `CTRL + SUPER + Left / Right` |
| Move across displays and station edges | `SHIFT + CTRL + SUPER + arrows` |

The **Keybindings** tab checks personal conflicts before applying a change.
Choose modifiers, capture the key, then Apply. Conflicting bindings stay inactive
until you choose another combination or explicitly approve replacement.

Station replaces Omarchy’s numbered workspace shortcuts and the grouped-window
focus shortcuts on `CTRL + SUPER + Left/Right`. Disabling or removing Station
restores the defaults and the stock widgets it temporarily hid.

## Make it yours

The **Settings** tab controls follow-focus behavior, station grace delay, minimum
station count, visibility of Omarchy’s Workspace and Display widgets, and whether
the panel opens beside its bar icon or centered on the current monitor.

Colors, typography, spacing, and controls follow the active Omarchy theme.

## Update or remove

```bash
omarchy plugin update yakumy.station
omarchy restart shell
```

To remove Station:

```bash
omarchy plugin remove yakumy.station
```

Preferences and wallpaper copies are retained for a later reinstall. Removal
cleans up Station’s runtime bindings and workspace rules, restores the stock
widgets it leased, and neutralizes its saved Single/Mirror rules. If the shell
was unavailable throughout removal, run `hyprctl reload` once it returns.

<details>
<summary><strong>Where Station keeps its data</strong></summary>

| Data | Location |
| --- | --- |
| Preferences | `~/.config/omarchy/station/config.json` |
| Runtime state and recovery | `~/.local/state/omarchy/station/` |
| Prepared wallpaper copies | `~/.local/state/omarchy/station/wallpapers/` |
| Managed display section | `~/.config/hypr/monitors.lua` |
| Managed window section | `~/.config/hypr/looknfeel.lua` |

Station changes only its marked sections, with a backup and validation.
Workspace migrations are journaled before moving windows and can resume after
an interruption. It does not edit Omarchy’s packaged files.

</details>

## Development

Start with the [documentation index](docs/README.md). [AGENTS.md](AGENTS.md) lists the
rules for changing Station.

```bash
python3 test/run.py        # portable checks
python3 test/run.py all    # everything, needs a Wayland session
```

These checks do not change your desktop configuration. See [Testing](docs/testing.md).

---

<div align="center">
  <strong>Station is free and open source.</strong><br>
  <a href="LICENSE">Apache License 2.0</a> ·
  <a href="https://github.com/Yakumy/Station/issues">Report an issue</a>
</div>
