<!-- summary: What Station must and must never do: scope, principles, who owns which setting, security. Index of the per-feature contracts. -->
# Contracts

This page states what Station must do and what it must never do. It describes current
behavior. If the code disagrees, one of them has a bug, so find out which. The
[platform findings](platform-findings.md) hold the evidence behind platform claims.

## Find the contract

<!-- index contracts -->
| Read | For | Tokens |
| --- | --- | --- |
| [Station actions and events](contracts/actions.md) | Switching, sending and moving windows, direction, starting station, Omarchy renumbering (workspace authority), follow focus, compositor events. | 1500 |
| [Bars](contracts/bars.md) | Per-monitor bars: sections, dragging, click targets, plugin widgets, presence, position, size, style, background and blur. | 2000 |
| [Color Match](contracts/color-match.md) | ICC profile controls, what each one changes in the profile, storage, live apply and rollback. | 1100 |
| [Display edits](contracts/displays.md) | Modes, geometry, the marked block in monitors.lua, preview, evacuation, Keep and Revert, the internal Off flag, enabling outputs, screen recovery. | 2400 |
| [Station indicator and open apps](contracts/indicator.md) | How fresh the bar's station number is, indicator styles, Compact mode, app icons, drawer. | 1000 |
| [Keybindings](contracts/keybindings.md) | Default combos, IPC methods, conflict sources and statuses, unbind rules, the key picker. | 900 |
| [Stock widgets, restart and removal](contracts/lifecycle.md) | Hiding and restoring Omarchy's own widgets (leases), what a restart keeps, what removal cleans up. | 800 |
| [Panel](contracts/panel.md) | Frame size, styles, tabs, keys, the Workspaces tab, dropdown scroll hints, text size, brightness, reopening after a bar rebuild. | 2000 |
| [Wallpaper](contracts/wallpaper.md) | Modes and controls, theme and background choosers, framing, Span, Follow, theme intros, image safety. | 2200 |
| [Windows tab](contracts/windows.md) | Gaps, Dwindle split, rounding and animation speed: ranges, the save and apply sequence, the preview. | 800 |
| [Workspace numbering](contracts/workspaces.md) | Workspace IDs, the saved map, migrations and their journal, Station/Repetitive/Non-repetitive modes, how many stations exist, more than four outputs. | 2200 |
<!-- /index -->

## What Station is

Station is a Quickshell plugin with QML, JavaScript, a little generated Lua and one
bounded Perl helper. It ships no compiled binary. Its one concept is the **station**:

- Switching a station switches every output together.
- Sending a window to a station keeps it on the same output.
- Unplugging an output merges its windows into a survivor without changing their
  station.

Station does not provide a standalone CLI, HDR, VRR or color management, self-update
logic, or management of more than three independent outputs.

## Principles

1. Install, update and removal use the stock `omarchy plugin` commands. Station makes
   no network access.
2. Station works when enabled. It has no setup step.
3. Station writes only its own files and its marked sections in `monitors.lua` and
   `looknfeel.lua`, always with a backup. Each file keeps its newest five Station
   backups (`<file>.bak.station.*`); a write removes older ones. It never edits `hyprland.lua`,
   `bindings.lua` or anything under `/usr/share/omarchy`.
4. Every value that reaches Lua or argv is validated.
5. Every asynchronous operation is checked against a generation.
6. The UI uses theme tokens only (see [Design system](design-system.md)).

## System authority

Hyprland and Omarchy own shared settings. Station observes them and persists only an
explicit edit.

| Setting | Authority | Station behavior |
| --- | --- | --- |
| Enablement, mirror source, geometry, scale, rotation, mode | Applied Hyprland state | Observe on reload, hotplug and every 1.5 s. Migrate workspace bookkeeping to the actual independent outputs. |
| Global gaps, Dwindle split, rounding, window animation speed | Hyprland options | Read on startup, reload and while the panel is open. Persist only an edited control. |
| Bar monitor rows, focused-monitor menu position | Omarchy shell config | Adopt changed rows. Discard superseded pending writes for those rows. |
| Global blur enabled, passes | Hyprland, except while a bar is set to Blur | Blur the user enabled stays untouched. While it is off and a bar is set to Blur, Station turns it on at runtime for that configuration, and returns the values it found when no bar wants it. Never written to a file. See [Bars](contracts/bars.md#bar-background-blur). |
| Global blur size | Hyprland | Never changed. |
| Personal keybindings | Hyprland and Omarchy bindings | Report conflicts. Do not replace personal binds without approval. |
| Wallpaper | Omarchy under Follow, otherwise Station's explicit choice | See [Wallpaper](contracts/wallpaper.md#wallpaper). |
| Brightness, text size | Omarchy commands | Connector-specific reads and writes. |
| Workspace numbering | Station while enabled | Omarchy's per-monitor reconcile is off. See [Workspace authority](contracts/actions.md#workspace-authority). |
| Station IDs, lanes, journal, UI preferences | Station | Persist and recover independently. |

Consequences:

- A runtime change from a terminal appears in Station but is not written to a Lua file.
  A later reload applies the files normally.
- `config.json` may cache observed display values, but they never enforce state.
- DPMS or screen blanking is not disablement.
- A mirrored sink never receives a workspace column, even when the source has a higher
  lane.

## Concepts that must stay separate

| Concept | Meaning | Stored |
| --- | --- | --- |
| Identity | Key from `description`. If two connected monitors share it, append `@<connector>`. | `config.json` |
| Lane (1 to 4) | Preferred order of an output | `config.json` |
| Slot | Current dense index in the committed map | `workspace-map.json` |
| Role | Displayed ordinal of a lane among those present | Never |

With lanes 1 and 3 present, the panel shows roles Primary and Secondary, and the slots
are 1 and 2.

## Security

- Use argv arrays or fixed scripts with validated positional arguments. Never interpolate
  device text into shell or Lua.
- Never put file text in argv, where another local account can read it from the process
  list. A transaction that compares or writes `monitors.lua`, `looknfeel.lua`, the
  Omarchy Off flag or the Color Match file reads the text from stdin.
  `Transactions.stdinParts` sends the parts in order and argv carries only each part's
  UTF-8 byte length. The script reads each part with `read_part` and then requires
  end of input with `end_input`. A short, overlong or malformed input exits 2 before
  the target changes. `CompositorLane.enqueue` takes the text as its fourth argument,
  writes it once the process starts and then closes stdin. Keep writes its own
  `Process` stdin the same way.
- **Connector:** must match `^[A-Za-z0-9_.:-]{1,64}$`, then may reach Lua (escaped) or argv.
- **EDID-derived fields** (`description`, `make`, `model`, `serial`) are untrusted: use
  them for matching and display only.
- Modes must match the monitor's allowlisted `availableModes` exactly.
- The bridge exposes detached data and a closed action list, never a QObject. The
  replacement-bar API exposes no generic command.
- Atomic file writes refuse symlinks and change only marked sections.
- Logs contain no command lines with unvalidated input.

## Performance targets

Press-to-switch has a target of p50 under 120 ms and p95 under 180 ms. [LIVE] Twenty
physical key samples measured p50 66 ms and p95 68 ms during the platform gate.
