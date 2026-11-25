<!-- summary: ICC profile controls, what each one changes in the profile, storage, live apply and rollback. -->
<!-- code: lib/color/** -->
# Color Match

Color Match makes monitors agree on white. Each adjusted monitor gets one ICC v4
display profile, and Hyprland applies it through its own color pipeline (it builds a
3D LUT with lcms2). Nothing else is installed.

| Control | Range | Default | What changes in the profile |
| --- | --- | --- | --- |
| Temperature | 4000 to 9000 K, steps of 100 | 6500 K | Per-channel gains along the Planckian locus, relative to 6500 K |
| Tint | −100 (green) to +100 (magenta) | 0 | Up to 30% less green, or less red and blue |
| Brightness | 50 to 100% | 100% | All three gains. It can only dim. The track runs on to 150% so 100% sits in the middle; past 100% the knob returns and the row says 100% is the maximum. |
| Gamma | 0.60 to 1.40 | 1.00 | The shared tone curve: the sRGB curve raised to 1/gamma. Higher darkens midtones. |
| Saturation | 0 to 200% | 100% | A Rec. 709 luminance-preserving saturation matrix. 0% is black and white. |

- Gains are normalized so the brightest channel is 1 before Brightness, so no channel
  clips. The gains and saturation go into the colorants (`rXYZ`, `gXYZ`, `bXYZ`) as
  `sRGB × (gains × saturation)⁻¹`. lcms inverts that description, so the screen receives
  the corrected signal. Every slider puts its default in the middle of its track.
  Saturation 0 has no inverse, so the matrix uses 0.2% instead;
  lcms then sends every color as grey within one code value. All channels share one
  tone curve, because Hyprland cannot represent split curves. The profile has no `vcgt` tag: see
  [Platform findings](../platform/color-match.md#color-match-icc-profiles-2026-11-11).
- Settings are stored in `config.colorMatch` by display identity, so they follow a
  monitor to another connector. A monitor at all defaults has no entry and no profile.
- An HDR monitor (`cm` `hdr` or `hdredid`) gets no profile, because an ICC replaces
  its HDR preset. The tab disables the controls for it and says why.
- Station owns `toggles/hypr/station-color.lua`, which Omarchy loads after
  `monitors.lua`. It calls `hl.monitor({ output, icc })` with only those two fields,
  which keeps the monitor's mode and position. Each call checks that the profile file
  exists and runs under `pcall`, so a missing profile never becomes a config error.
- Profiles are named `<connector>-<hash>.icc` from their bytes, so Hyprland never
  reuses a stale file. Unused profiles are deleted after a successful apply.

A slider applies on release through the fixed `Transactions.colorMatch` script:

1. Write the new profiles, then compare the toggle file with the version the owner read.
2. Suspend autoreload, replace the file atomically, and apply.
3. A changed or new profile applies live with `hyprctl eval` of the changed monitors'
   rules: no reload. A connected monitor that loses its profile (Reset, or all defaults)
   needs one `hyprctl reload`, because Hyprland cannot clear an ICC live (`icc = ""` is
   rejected).
4. Restore autoreload on every exit. A failed apply restores the file only if it is
   still ours and reloads. The owner then restores the previous settings and saves
   nothing.

The tab shows the dragged value live and applies on release. Controls stay disabled
while an apply runs, and an edit is refused as busy unless Station is idle, because a
profile reload would cancel a display preview or migration. Startup, reload and hotplug reconcile the file with the saved
settings, and a matching file costs nothing. A disconnected connector keeps its row,
so unplugging never forces a reload. Removal deletes the file before its reload.

The control frame contains only the five equal-height adjustment rows. HDR,
busy and failure messages appear in the row hints. There is no Reset/status row
or reset action in the panel bridge; returning sliders to their neutral values
still removes the monitor's adjustment through the normal apply path.
