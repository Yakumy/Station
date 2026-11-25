<!-- summary: Background layers, choosers, Screen remap crash, image decoding limits, theme and background change signals, theme switching. -->
<!-- code: lib/wallpaper/** lib/platform/ScreenMoveRemap.qml -->
# Wallpaper and themes

Dated sections are investigations, oldest first. A later one can supersede an earlier one.

## Wallpaper integration (2026-10-11)

- [SRC] Omarchy 4.0.3-1 renders its wallpaper with background-layer PanelWindows.
  `omarchy theme bg set` changes `~/.local/state/omarchy/current/background` and
  calls the background IPC target. Theme application can regenerate the same
  current-theme image pathname. Station must snapshot pinned images, not retain
  that pathname as an immutable source.
- [SRC] `omarchy file select --title ... --extensions ...` uses the desktop portal
  and prints a local filename; exit 1 means no selection, exit 2 chooser failure.
  There is no need for Zenity or a private chooser dependency.
### Screen remap and layer loss

- [SRC] Omarchy removed the host's `Ui.ScreenMoveRemap` on 2026-11-01
  (basecamp/omarchy#17229) because Hyprland 0.57 moves a mapped layer surface with
  its monitor. A plugin that still names the host type fails to load: the bar falls
  back to `omarchy.bar` and the service reports `Ui.ScreenMoveRemap is not a type`.
  Station keeps its own copy in `lib/platform/ScreenMoveRemap.qml`, which remaps
  layer surfaces after output origin changes on Hyprland before 0.57 only. The
  bar and the wallpaper surfaces use it. Wallpaper surfaces have an empty input
  region and no keyboard focus. Their lifetime follows the persistent service.
- [LIVE] On 2026-11-10, with omarchy-dev 4.0.0.r7647 and Hyprland 0.57.1, the bar,
  the wallpaper surfaces and the service loaded with the local copy on two outputs
  (`HDMI-A-1`, `DP-5`). No monitor move was exercised.
- [LIVE] On 2026-11-23, with Hyprland 0.57.2, quickshell 0.3.2.r7 and Qt 6.12.0,
  connecting and disconnecting HDMI killed the shell 14 times in ten minutes. Every
  core has the same stack: a QML `Timer` writes a property, the window's `visible`
  binding shows it, quickshell sets the content's parent, and inside Qt's
  `QQuickItemPrivate::refWindow` a second binding calls `QQuickItem::setParentItem`
  and dies in `QQuickItemPrivate::dirty`. `Cannot use same item on different windows
  at the same time` and `closelayer>>omarchy-bar` come just before. The timer was
  Station's remap guard. The only hosted item bound that way was Reel 0.5.1's
  `parent: root.QsWindow.window ? root.QsWindow.window.contentItem : root`.
- [LIVE] An isolated quickshell with one 8 px surface separated the two causes: the
  Reel binding with the remap segfaults, the same binding with no remap survives, and
  the remap without the binding survives. Station cannot control a widget's bindings,
  so it must not rebuild the bar window where the compositor does not need it.
- [LIVE][SRC] On 2026-10-27, repeated Station Mirror/Single/Extend changes left
  Hyprland reporting both `eDP-1` and `HDMI-A-2` enabled and unmirrored, while
  `hyprctl layers -j` showed no layer at all on `eDP-1` (neither
  `omarchy-background` nor `omarchy-bar`). The running shell had logged
  `attempted to use dangling screen object` and then an eDP-1 removal that its
  Hyprland integration said was not previously tracked. This is a stale Qt screen
  list, not a wallpaper path or decode failure. After a committed/reverted Station
  topology change, compare active independent Hyprland outputs with
  `Quickshell.screens`. A shell restart and `hyprctl reload` both left eDP-1
  absent. Explicitly disabling eDP-1 and restoring its exact rule republished the
  Wayland output; both `omarchy-background` and `omarchy-bar` returned while the
  shell stayed healthy. Recovery therefore cycles a missing output once after
  preview recovery is disarmed, and only with another active shell-visible output
  as the survivor.
### Framing and image safety

- [SRC] [Wallpaper Cutter](https://github.com/renanmt/omarchy-wallpaper-cutter)
  documents per-output bottom-layer surfaces above stock, crop preview and
  native-resolution exports. Station uses the layering approach, but renders
  shared source-space crops directly and installs no theme hook or image processor.
- [QTTEST] Production WallpaperLayout pointer tests preserve output topology,
  clamp pan, keep the image fixed while zooming, and support keyboard nudges.
  Isolated Quickshell renders use installed UI tokens with dark and light
  palettes; they do not establish three-display hardware behavior or theme
  transition animation equivalence.
- [QTTEST] Per-monitor framing in `WallpaperLayout` is tested with Qt pointer, wheel and
  key events, and the desktop renderer by pixel. Real pointer feel through the bridge,
  and a framed surface on a real output, have not been tested live.
- [QTTEST] Qt 6.12 exports its own `QtQuick/Color`. In an isolated Quickshell root, bare
  `Color` in a file importing `QtQuick` then `qs.Commons` resolves to `QQuickColor`, so
  `Color.popups` is undefined and surfaces paint white. Logs from live sessions on the same
  Qt show no such error, and the reason for the difference is not established.
  `Commons.Color`, through `import qs.Commons as Commons`, resolves correctly in both.
- [SRC] Qt's PNG handler calls `png_read_info()` and copies all PNG text entries
  into Qt strings before its raster allocation. Libpng's default limits are per
  ancillary chunk and by chunk count, not by aggregate decompressed text bytes;
  therefore the QImage raster limit does not bound compressed text metadata in
  the shared shell process.
- [SRC] A portal result previously entered `draft.source` immediately, feeding
  unchanged foreign bytes to `WallpaperLayout.qml` and `WallpaperImage.qml`
  before Apply. Selection now invokes the core-Perl streaming helper by argv.
  The helper detects formats by magic bytes, caps total input/chunks/raster, and
  writes only bounded rendering chunks for PNG. QML receives only the private
  prepared path. Old unmarked pinned images are gated and restaged before use.

## Theme and background change signals (2026-11-05)

- [SRC] `omarchy-theme-set` replaces `current/theme` with a rename, writes
  `current/theme.name`, and updates the `current/background` link with `ln -nsf`.
  `omarchy-theme-bg-set` updates only the link. Both also call shell IPC, and only
  `omarchy-theme-set` runs the `theme-set` hook, after its slower app updates.
- [LIVE] In a scratch directory, the same operations produced `inotifywait` events for each
  step, including a rename over the link and over an image.
- [LIVE] The former poll cost 5.1 ms of CPU per check: 2.03% of one core at 250 ms and
  0.34% at 1.5 seconds.

## Theme switching with a chosen background (2026-11-16)

- **[SRC]** `omarchy-theme-set` (omarchy-dev on 2026-11-16) chooses a new theme's
  background from `~/.config/omarchy/backgrounds/<theme>/` and the staged theme's
  `backgrounds/`, sorted by path. When the previous theme differs, it uses the path in
  `~/.local/state/omarchy/theme-backgrounds/<theme>` if that file exists, otherwise the
  first. A remembered path under `~/.local/state/omarchy/current/theme/backgrounds/` is
  remapped to the staged copy, so writing that form selects a bundled background. When
  the theme is unchanged it cycles to the next background instead, so Station uses
  `omarchy theme bg set` for the current theme.
- **[SRC]** It writes `theme.name` before it links `current/background`, and links it
  before it returns. A theme read started after the command exits sees both.
- **[SRC]** The command returns once the visible retints finish; the rest run detached
  because Station's process has no terminal on stdin.
- **[QTTEST]** The Wallpaper tab harness opens both carousels, browses, wraps, chooses,
  closes on Escape and targets the selected monitor in Per monitor. A render with the
  28 installed themes centered the chosen card. Keys were driven through the
  carousel's functions, not real key events.
- **[INFER]** The remembered-file handoff is not a public Omarchy interface. Its
  behavior is covered by unit tests against a fake `omarchy`, not by a live switch.
