# Unreleased

- Start on Station 1 after login, instead of the station that was open at shutdown.
- Add a Color Match tab after Windows. Select a monitor and adjust its Temperature,
  Tint, Brightness, Gamma and Saturation until its white matches your other monitors.
  Each change applies live on release, as a color profile that Hyprland applies itself,
  with nothing extra to install. Reset returns a monitor to its own colors. Settings
  follow the monitor to another port. HDR monitors are left alone. Saturation goes
  down to 0% for a black-and-white screen.

- Include every enabled monitor in the Windows animation preview. On one monitor,
  swap the two windows twice and restore WINDOW left / NEXT WINDOW right.

- Move the bar by holding a widget before dragging. Keep the Station panel on the
  current bar edge after relocation, including Pill bars and custom heights.

- Keep the shared edges of joined buttons square throughout the panel. Workspaces
  and Wallpaper mode selectors round only the group's outer corners with the theme.
- Register `CTRL + SUPER + Up/Down` for TTB/BTT station navigation and show them in
  Keybindings. BTT Up reaches the next existing station; Down reaches the previous one.
- Fix BTT and TTB window moves at the edge of side-by-side monitors with different
  heights. Up and Down step to the adjacent station on the same monitor instead of
  treating the other monitor as a vertical neighbor. Correct native moves that cross
  to the wrong monitor, while keeping native tile movement.
- Keep widgets in Omarchy's `centerBegin` and `centerEnd` sections visible beside
  the centered clock, including vertical and Pill bars. Preserve tray-section
  widgets in the tray drawer, settings updates, drag moves and leased placements.
- Register one bar IPC handler for all outputs and use explicit process-exit
  parameters in display controls. Update host-dependent test fixtures.

- Add a Workspaces tab after Displays. Its locked layout shows each monitor's role and the
  workspaces it gets, and it updates as you change the controls. Choose Sync (every
  monitor switches together), Repetitive (every monitor numbers its own workspaces from 1,
  exactly as Omarchy 4.5 does) or Non-repetitive (each number belongs to one monitor, as in Omarchy
  4.0). Sync offers three stations, and the other modes start with five workspaces on each
  monitor. Use − and + on a monitor in the layout to change its workspaces (up to 10 per
  monitor), and in Non-repetitive drag workspace numbers onto the monitor you want (up to
  20 in all; keys reach 1 to 10). Pick the bar indicator style, a compact mode (Off lists
  every workspace with Omarchy's square for the current one, On hover reveals them on
  hover, On shows only the current one) and whether open apps show. As in Omarchy's
  indicator, empty workspaces you are not on are dimmed. Changes wait for Apply, and Cancel
  undoes them. Changing the mode or the workspaces moves windows with the same journaled
  migration as a display change. Open apps move here from Settings. With one monitor the
  mode selector is disabled.
- Stop window and display edits from piling up `looknfeel.lua` and `monitors.lua`
  backups. Station keeps the newest five of each file's backups and removes older ones.
- Keep the workspace assignment you already had. On a fresh install Station reads your
  Hyprland workspace rules first: rules that split the numbers between monitors start
  Non-repetitive with your numbers on each monitor, and rules that give each monitor its
  own block start Repetitive with your counts. Without such rules it starts in Sync.
- Remove the dot indicator style, which did not work in the compact modes. A saved dot
  style shows as S1 S2 S3 (W1 W2 W3).
- Hide Omarchy's Display icon by default on a fresh install, as the workspace indicator
  already is.
- Make Repetitive use Omarchy 4.5's own workspace blocks (1–10 on the laptop, 11–20 on
  the next monitor) instead of Station's numbering. Omarchy's renumbering on reload and
  hotplug runs as without Station.
- Rename Settings' workspace indicator switch to Show Omarchy default workspace
  indicator. It shows or hides Omarchy's own workspace indicator in every mode, next to
  Station's widget.
- Fix Station failing to load on newer Omarchy builds, where the bar fell back to the stock
  bar and the wallpaper and panel stopped working. Omarchy removed `ScreenMoveRemap`, so
  Station now carries its own copy.

- Play matching theme intros with the saved Span and per-monitor wallpaper framing
  when OWE supports source rectangles, preserving the crop through the final still.

- Frame the wallpaper separately on each monitor in Same on all and Per monitor: drag inside
  a monitor to move the image, scroll to zoom, and use Reset frame to go back to a centered fill.
- Show the display preview's Keep/Revert countdown on every tab. On other tabs it ran out
  unseen, and reverting could turn a monitor off with no warning.
- Stop the panel reloading when a bar is turned on or off. That control alone wrote
  `shell.json` while the panel was open, which rebuilt every widget, the panel included.
- Keep the panel open when another monitor is turned off, mirrored or left out by Single.
  It still moves when its own monitor is the one leaving.
- Make a bar's on/off switch move smoothly. The switch now finishes its throw before the
  bar is built or removed, which used to freeze it on the same thread.
- Fix a window jumping to the next station when moved to another monitor with
  Super+Shift+Ctrl+arrow. Omarchy's bind on that key was never removed, so one press moved
  the window twice. Station now removes a replaced bind in any modifier order.
- Fix windows on the second monitor ending up in station 6 or later after a reload, a theme
  change or a hotplug. Station turns off Omarchy's per-monitor workspace renumbering while
  it is enabled, and removes the Super+Shift+Alt+arrow workspace moves that do the same.
- Make the Blur bar background work when Hyprland's global blur is off, without blurring
  see-through windows.
- A Pill bar ignores the outer gap beside it and keeps its safe space from windows too, which
  also centers a Pill bar's content between monitor edge and windows.
- Windows tab preview windows follow Border roundness at preview scale, use the accent, and
  the tab gains its bottom line.
- Keep a safe space between a Pill bar and the monitor edge and ends.
- Apply the outer gap beside Solid and Blur bars but not beside Transparent bars (Omarchy
  default or Pill), through runtime per-monitor workspace rules.
- Stop reporting a conflict for Omarchy 4.5.0's Super+Ctrl+Shift+arrow move-to-monitor
  binds. Station replaces them and still works on older Omarchy. Reminder: remove
  Station's own binds in 5.0.0.
- Reorganize the code without changing behavior or persisted formats: Service is now a
  composition root, runtime code lives in feature folders, all checks live under `test/`
  with one runner, and all documentation lives in one `docs/` set.
- Restore wallpaper image selection through the replacement-bar bridge.
- Enable key capture on the opened Keybindings tab and return to Wallpaper after
  the image chooser closes. Name tab identities without changing numeric IPC.

# 3.0.0 — System settings are authoritative

- Merged Nitai's PR #5 with its original author and commit preserved.
- Replaced background monitor/appearance enforcement with compositor observation.
- Adopt external display state, mirror sources, bar settings and personal binding
  conflicts; preserve workspace journal identity across topology changes.
- Put Station's saved monitor rules before personal overrides and migrate older
  blocks with backups. Add bounded physical-presence guards for cold startup.
- Persist individual window controls in `looknfeel.lua`, read back applied values,
  and report personal overrides. Global rounding now also follows shell corners.
- Respect global blur and outer gaps instead of restoring Station-only overrides.
- Cancel previews on external configuration changes; compare source files before
  saving and preserve newer edits during rollback.
- Follow wallpaper and theme changes through filesystem events instead of a 250 ms poll.
- Fix Extend and Mirror doing nothing after a saved Single: leaving Single now turns the
  other outputs back on.
- Fix Single on the laptop display after `omarchy-hyprland-monitor-internal off`: park
  Omarchy's Off flag during the preview so its recovery cannot cancel it. Revert returns
  the flag.
- Fix intermittent `Could not focus the surviving display` by waiting up to 2 seconds for
  an output that was just enabled.
- Fix On → Keep after `omarchy-hyprland-monitor-internal off`: hand off the
  generated Off toggle during the checked save, preserving Revert and rollback.
- Restore direct Windows slider application on release: save with file watching
  suspended, remove the fixed one-second wait, and avoid full reload cursor jumps.
- Fix Windows sliders jumping back during a save: retain the selection through
  dragging and applied-value read-back, including replacement-bar snapshots.
- See [system authority](docs/contracts.md#system-authority) for semantics and hardware limits.

## Earlier development history

### Windows controls

- Added Windows after Bar, with two-window geometry and side-swap preview.
- Added persistent gap, Dwindle split, rounding, and animation controls, including
  bar-thickness reference marks and replacement-bar support.

- Corrected next-window split direction, excluded enabled bar edges from outer
  gaps, matched the shared dotted layout canvas, and made speed previews run once.
- Limited animation speed to nine stops across 0–2× with 1× centered; preserved
  fractional speeds and full slow-preview duration.
- Reserved inset bar surfaces in full so Blur, Transparent and Pill cannot
  overlap tiled windows when the bar-facing window gap is zero.
- Aligned every bar presentation with the monitor edge and removed pill outer
  margins while retaining full window-space reservation.
- Kept window roundness independent of shell/bar corners using application rules.
- Added full monitor topology to Windows with neutral per-monitor bar previews,
  Pill segments, two windows per monitor and a cross-monitor animation exchange.
- Aligned the Layout heading and removed the selected-monitor caption.
