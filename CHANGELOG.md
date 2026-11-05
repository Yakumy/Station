# Unreleased

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
