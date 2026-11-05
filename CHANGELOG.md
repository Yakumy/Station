# Unreleased

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
