<img src="./docs/assets/station-banner.png" alt="Station" width="100%">

# Station

Station is an Omarchy plugin for intelligent multi-monitor management that:

- **Creates logical workstations** by syncing Hyprland workspaces across your monitors into an abstraction we call a **station**.
- **Switches and moves windows across monitors** with fast, keyboard-driven controls.
- **Handles monitor hot-plugging automatically**, adapting between dual- and single-monitor layouts.
- **Preserves your workspace state and position** when monitors are disconnected or reconnected.
- **Integrates natively with Omarchy**, including the Quattro bar and Hyprland configuration.
- **Provides a powerful CLI** for configuring, controlling, and monitoring your stations directly from the terminal.

> [!INFO]
> v1.0 only supports dual/single monitor setups for now.

## What it does

Station pairs Hyprland workspaces two at a time. In dual-monitor mode, each
station spans one workspace on your primary monitor and one on your
secondary — station 1 is workspaces 1 and 2, station 2 is workspaces 3 and 4,
and so on up to station 5. Switching stations moves both halves together;
directional movement lets you cross station boundaries or move a window
between the two monitors within a station.

When you're down to one monitor — either by choice (`station mode single`)
or because a cable came out — Station collapses each station's two
workspaces into one, on whichever monitor is left, without losing which
window belonged to which station. Reconnect the second monitor and it
expands back to the dual layout automatically, still on the correct
station.

The bar indicator (`[S1]`–`[S5]`) shows your current station, styled to
match your active theme. It's only shown in dual-monitor mode — in single
mode there's nothing to disambiguate, so it stays out of the way.

<img src="./docs/assets/station-indicator.png" alt="Station" width="100%">

<div align="center" width="100%">
  <video
    src="https://github.com/user-attachments/assets/f74d1c0c-f4ea-4b0b-a396-f4c87e75d474"
    width="100%"
    controls>
  </video>
</div>

## Requirements

- Hyprland 0.56.x
- Omarchy 4.x or newer (Quattro)
- Exactly 2 monitors connected to run `station init`

`install.sh` checks all three before touching anything on your system, and
refuses cleanly if they're not met.

## Install

```
omarchy plugin add https://github.com/Yakumy/Station.git --enable
cd ~/.config/omarchy/plugins/yakumy.station
./install.sh
station init
```

`omarchy plugin add` clones the plugin into place and registers the bar
widget. `install.sh` verifies your environment, installs the `station`
command to `~/.local/bin`, wires the Hyprland keybindings in, and positions
the indicator in the bar. `station init` is the one step that's deliberately
separate — it's the moment Station actually starts managing your
workspaces, so it's never run automatically on your behalf.

## Update

```
station update
```

This checks whether a newer version is available, shows you the version
change, asks for confirmation, then pulls and reapplies the update. Your
configuration (primary/secondary monitor, direction, current mode) is
stored outside the plugin directory and is never touched by an update.

## Uninstall

```
station delete
```

This removes the `station` command, your saved configuration, the Hyprland
keybinding integration, the bar indicator entry, and the plugin itself. If
any step can't complete automatically, it will print the exact manual
command to finish the job — nothing is left half-removed silently.

## Configuration

```
station set monitor <name> <primary|secondary>   # e.g. station set monitor HDMI-A-2 primary
station direction <left2right|right2left>          # which physical arrow means "next station"
station direction                                   # print the current direction
station mode single <primary|secondary>             # collapse to one monitor
station mode dual                                    # restore dual-monitor layout
```

`station set monitor` requires dual-monitor mode and exactly 2 monitors
connected. By default Station picks whichever monitor is positioned at
`0x0` as primary; setting it explicitly overrides that permanently.

## Keybindings reference

| Keys                                              | Action                                                      |
| ------------------------------------------------- | ----------------------------------------------------------- |
| `Ctrl + Super + F1`–`F5`                          | Switch to station 1–5                                       |
| `Shift + Ctrl + Super + F1`–`F5`                  | Move the active window to station 1–5, and follow it        |
| `Shift + Super + Alt + F1`–`F5`                   | Move the active window to station 1–5, without following    |
| `Ctrl + Super + Left / Right`                     | Switch to the previous/next station (direction-aware)       |
| `Shift + Ctrl + Super + Left / Right / Up / Down` | Move the active window across a station or monitor boundary |

All of these remain active and functional in single-monitor mode — with
only one monitor, a "station" and a workspace are the same thing, so
nothing behaves inconsistently.

## Troubleshooting / Recovery

**The indicator isn't showing up.**
It's only visible when Station is initialized, running, and in dual-monitor
mode. Run `station status` — if it says "not initialized" or "stopped," run
`station init`. If it says "single," that's expected; the indicator hides
itself there by design.

**A mode switch (`station mode single/dual`) seems to have left windows in
the wrong place.**
Run `station status` and `hyprctl workspaces` to see the actual current
state, then run `station mode dual` (or `single <role>`) again — mode
transitions are idempotent and safe to re-run.

**Hyprland showed an error banner right after installing, before you'd run
`station init`.**
This is expected to be resolved by `station init` itself — Station's
Hyprland integration is written to no-op safely until you initialize it. If
you still see an error after running `station init`, that's a real bug —
please open an issue with the exact error text.

**You unplugged a monitor and things look wrong.**
Station listens for Hyprland's monitor-added/removed events and migrates
automatically. If it doesn't seem to have triggered, run
`station reconcile` to force a manual re-sync against your currently
connected monitors.

**You want to start completely over without reinstalling.**

```
station stop
station init
```

`station stop` disables Station without removing it; `station init` picks
primary/secondary fresh (or respects a previously saved explicit choice via
`station set monitor`).

**Nothing above fixes it.**
`station delete` followed by a fresh `omarchy plugin add ... --enable` +
`install.sh` + `station init` is a safe, clean reset — configuration and
Hyprland integration are fully removed and recreated from scratch.

## License

Apache License 2.0 — see [LICENSE](./LICENSE).
