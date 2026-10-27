# Wallpaper contract — 2026-10-11

The panel tabs are Displays, Bar, Wallpaper, Keybindings, Settings. Wallpaper follows
the existing two-column composition: layout on the left, controls on the right,
notice at lower left, Cancel/Apply at lower right. The layout and settings frames
are the same 370-unit height used by Displays, and the layout reuses its dotted
grid. `WALLPAPER` sits above the settings frame, parallel to `LAYOUT`, while a
full-width segmented Mode control leads the frame; the remaining rows contain
only the image actions and Follow Omarchy switch. The frame follows Displays'
five equal row heights, leaving the unused rows empty. In Per monitor mode the
monitor selector appears with the image actions, not in the Mode row. All chrome uses installed
`qs.Ui` components and `qs.Commons` tokens. The sole filled action is Apply.

Modes are Same on all, Per monitor, and Span. Default is Same on all with Follow
Omarchy wallpaper enabled. A local file is chosen through `omarchy file select`;
close the keyboard-focused popout before opening the portal chooser, then reopen
Wallpaper when it exits. The service retains the draft through panel rebuilds.
The picker result is not a preview source: Station first streams it into a fresh
private directory through its bounded sanitizer, then updates the draft with
that prepared path. Selecting a file or changing a crop affects the preview
until Apply. Sanitization, decode, and snapshot errors retain previous settings.
Preference save failure restores them.
While Follow Omarchy wallpaper is enabled, Choose image leaves the panel open
and shows an urgent notice telling the user to turn Follow off; Omarchy remains
authoritative and no picker opens until the switch is disabled.

Active non-mirrored outputs come from observed Hyprland monitors, not the editable
Displays draft or workspace lanes. Disabled outputs vanish. Per-output choices
use the same physical identities as Model.js. A returning output recovers its
choice; a new one falls back to the common image. Mirror sinks inherit the source
image through the compositor. Wallpaper never emits monitor/workspace commands.

Span preserves logical output positions, gaps, rotations and relative dimensions.
Its monitor cards stay edge-to-edge where the logical outputs touch so the
continuous crop is not interrupted. Same and Per monitor previews paint the
compact named theme-space gap between touching monitor cards, matching the
Displays and Bar canvases.
The whole image is fitted into the canvas with side space as needed. The group
is uniformly scaled and translated over that fixed image; it cannot be split,
rotated or rearranged here. Pan is clamped to keep every crop inside the image.
Zoom 1 fits the group; wheel zoom up to 8 selects smaller regions. The native recommendation
is logical bounds × maximum output scale × crop zoom, rounded upward. It is a
quality recommendation, never a minimum file-size restriction. This preserves
logical continuity; it does not estimate physical DPI or bezel thickness.

Follow mode uses the live Omarchy background and a profile keyed by the current
theme name and canonical background pathname. Returning to an existing pair
recalls its framing while still reading Omarchy's current image; a new pair uses
centered framing. A short poll fingerprints the target as well as the path, so an
image replaced in place refreshes the panel and desktop surfaces. Mode
is global. The newest 64 profiles are retained; users can replace a recalled
choice with Use Omarchy wallpaper. When follow is off, a saved pinned profile
ignores theme/background changes. Turning follow off requires Apply to snapshot
the selected source; the theme may regenerate files in place, so a mere path
would not suffice. Panel tokens always follow Omarchy independently.

Polling is read-only, every 1.5 seconds. Stock theme transitions are not reproduced
by the per-output surfaces. Station does not rewrite Omarchy's symlink or infer
private wallpaper history. Omarchy remains authoritative for the current pair.
Changes during an unfinished follow-mode snapshot invalidate its callback; an
unapplied draft remains available with a notice. A finished commit may retain
the old pair's profile without replacing the newly selected pair's wallpaper.

Imports and snapshots use fresh private directories under Station state, quoted
positional argv, and no interpolation of filenames or EDID text into scripts.
The import helper recognizes PNG, JPEG, GIF, BMP, and WebP by magic bytes and
enforces a 128 MiB input limit. PNG parsing is streaming, with a 4,096-chunk and
256 MiB decoded-raster budget; only IHDR, PLTE, IDAT, IEND, and small rendering
chunks are retained. Text, ICC, EXIF, animation, suggested-palette, and unknown
ancillary chunks are discarded without decompression. The safe marker is valid
only for paths under Station's private wallpaper directory. Older unmarked pinned
choices remain absent from QML Images until the helper prepares replacement
copies and the config save is acknowledged. Image copies are retained after mode
changes, failed saves, disable and removal; there is no automatic cache eviction
in this version. Preferences live under `config.wallpaper` without changing the
enclosing config schema. Missing/invalid settings normalize to defaults. The
helper uses core Perl, already required by Omarchy; no external image processor,
network access, or extra package is needed.

The persistent service draws non-interactive bottom-layer surfaces above the
stock background. Default Same on all defers to stock; missing images also reveal
stock. Surface lifetime handles disable/removal and shell restart, with no hook
cleanup or background-daemon replacement. After Keep or Revert settles, Station
checks that every enabled, non-mirrored Hyprland output exists in Quickshell's
screen list. If Qt failed to recover an output and therefore lost the stock
background, Station cycles that output once only after preview recovery is
disarmed and only while another active output remains visible to the shell. It
then restores the exact validated mode, position, scale, transform, and cleared
mirror state. ScreenMoveRemap follows the host's position-change workaround.
Animated images are static first frames; HDR, video, bezel correction,
physical-DPI matching and image export are out of scope.
