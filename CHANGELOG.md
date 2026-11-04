
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
