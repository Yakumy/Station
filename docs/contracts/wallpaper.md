<!-- summary: Modes and controls, theme and background choosers, framing, Span, Follow, theme intros, image safety. -->
<!-- code: lib/wallpaper/** -->
# Wallpaper

Wallpaper is independent of workspace and monitor policy and emits no monitor commands.
Its modes are Same on all (the default, following Omarchy), Per monitor, and Span.
The five control rows are Mode (dropdown), Follow Omarchy theme (Yes/No dropdown),
Image, Theme background and Theme (buttons). The three buttons fill their
row's padded width, with the selected image filename, current background filename,
and current theme name beneath them. Per monitor shows `Selected: <connector>` above
the controls; the layout selects that monitor. Other modes leave that heading empty.
The theme buttons keep Station open and float a carousel over the layout canvas.
There is no Use Omarchy wallpaper or Reset frame button; framing remains
available through canvas gestures.

## Theme and background choosers

- Choose theme lists every Omarchy theme with a palette, from
  `~/.config/omarchy/themes` and `$OMARCHY_PATH/themes`, showing each theme's
  `preview.png`. `ListThemes.pl` builds the list with fixed argv; theme and file
  names stay JSON data. A cloned (`.git`) user theme contributes no symbolic link, as
  in `omarchy-theme-set`.
- Choose theme background lists the still backgrounds of the chosen theme, or of the
  current one: `~/.config/omarchy/backgrounds/<theme>/` first, then the theme's
  `backgrounds/`, in Omarchy's order. Videos are not offered.
- Left and Right (or `h`/`l`) browse and wrap, the wheel browses, Return, Enter or
  Space chooses, and a click centers a card or chooses the centered one. Escape closes
  the carousel without choosing and leaves the panel open. The carousel opens on the
  pending or current choice.
- While the carousel is open the canvas hides its monitors, image and hint, keeping only
  its frame and grid, and the carousel holds pointer input so nothing reaches the
  layout. The centered card, the one Return chooses, is 1.2 times a card's size and its
  neighbours 0.8 times. The name and position sit under the cards.
- The message line of the Cancel/Apply strip, where the tab shows notices and errors,
  reads `Press Enter to select · Esc to go back` while the carousel is open. In
  portrait the strip opens for it.
- The heading reads `THEME`, `BACKGROUND` or `BACKGROUND · <connector>` while it is
  open, with `← → TO BROWSE` on the right. The row hints add `· on Apply` to a pending
  theme or background.
- Choosing changes only the draft. Nothing reaches Omarchy before Apply, and Cancel
  drops the pending theme and background.
- A theme is global. Under Follow, every monitor previews the background the theme will
  open on: the one Omarchy remembers for it, otherwise its first. The preview uses the
  saved profile for that theme and background. With Follow off the wallpaper stays.
- In Per monitor, a theme background becomes the selected monitor's own image through
  the same safe import as Choose image, so it turns Follow off and the other monitors
  keep a private copy of their current preview. In Same on all and Span it becomes
  Omarchy's background and turns Follow on.
- Apply runs one Omarchy command first. A new theme records the chosen background in
  `~/.local/state/omarchy/theme-backgrounds/<theme>`, then runs
  `omarchy theme set <theme>`, so Omarchy opens the theme on that background with its
  own transition and intro. A background for the current theme runs
  `omarchy theme bg set`. Station saves the wallpaper profile only after a theme read
  started after the command exits names the new theme. A failed command keeps the
  choice and reports an error; a missing report frees Apply after 5 seconds.

## Framing and profiles

- Outputs come from observed Hyprland state. A returning output recovers its choice.
  Mirror sinks inherit through the compositor.
- Span preserves logical positions, gaps, rotations and relative sizes. The monitor
  group moves over a fixed image, zoom runs from 1 to 8, and pan stays inside the
  image. The recommended resolution is logical bounds × maximum scale × zoom. It is a
  recommendation, never a limit.
- Same on all and Per monitor frame each monitor separately. Dragging inside a monitor
  moves the image with the pointer, the scroll wheel zooms around the pointer, and with
  the canvas focused the arrow keys and `+`/`-` act on the selected monitor. Zoom runs
  from 1, the largest crop that still fills the monitor, to 8, so a frame never shows an
  empty edge. Frames are per monitor identity and per mode, are saved in the profile
  under `frames`, and take effect on Apply. A profile without `frames` loads with every
  monitor centered at zoom 1. A centered, unzoomed frame is not stored, so a monitor
  with no frame under Follow in Same on all stays on the stock surface. Choosing an
  image drops the frames made for the image it replaces.
- A canvas gesture draws from a local frame and reaches the controller when it settles,
  because the panel reads the draft through a polled bridge. The local frame ends when
  the draft answers, or after 1 second if the controller ignored it.
- Follow mode uses the live background and a profile keyed by theme and background
  path, keeping the newest 64. An `inotifywait` process watches Omarchy's
  `~/.local/state/omarchy/current` directory and the image's directory, and Station
  reads the theme once for each settled change. An image replaced in place also
  refreshes. If the watch ends unexpectedly, Station reads once and retries every
  5 seconds.
- With Follow off, a pinned profile ignores theme changes. Apply makes the snapshot,
  because a theme may rewrite the same path.
## Choosing an image and drawing it

- Choosing an image closes the panel first, because the native chooser needs focus.
  The panel returns to Wallpaper on success, cancellation and error. Accepting a
  safely prepared local image turns Follow off; cancellation leaves Follow unchanged.
- The service draws click-through bottom-layer surfaces above the stock background. The
  default mode leaves the stock surface visible.
- Animated images show a static first frame.
## Theme intros

- Under Follow, a matching theme intro uses the saved wallpaper crop on every output,
  including Span pan/zoom and per-monitor frames. Station keeps its still visible until
  OWE confirms that the crop has been presented on every output. The same normalized
  rectangles apply to the video and its fade into the final still; Station then resumes
  its saved image framing. The renderer holds the cropped opening frame until Station
  reveals it and releases playback, so the framing handshake does not skip the opening.
  The hold expires after two seconds if the covering client disappears. Playback
  remains one OWE decoder, never one player per screen.
- Framed intros require OWE's `source-rects` renderer API and `intro_path` status field.
  Older engines keep Station's still visible. Requests are scoped to the renderer's
  media generation; stale replies, missing images, unavailable outputs and engine errors
  cannot reveal an unframed video. Observation is bounded to a theme-change window and
  ends after a completed intro. Pinned wallpapers do not follow intros.
- For engines advertising `composition_handoff`, Station keeps its transparent layer
  mapped throughout playback, restores only its cropped image at the end, and waits
  for two render frames before acknowledging. OWE enables the stock background only
  after that acknowledgment. This avoids both a polling gap and the compositor's
  layer fade exposing the unframed wallpaper.

## Image safety

A selected path never reaches a QML `Image`. `SanitizeWallpaper.pl` runs with fixed
argv, recognizes PNG, JPEG, GIF, BMP and WebP by magic bytes, and writes a private copy.

- Limits: 128 MiB input, and for PNG 4,096 chunks and a 256 MiB decoded raster.
- PNG keeps only IHDR, PLTE, IDAT, IEND and small rendering chunks. It discards text,
  ICC, EXIF, animation and unknown chunks without decompressing them.
- Private image copies retain the source basename with the detected format extension,
  including across Apply snapshots, so the Choose image hint stays recognizable.
- Only marked paths under Station's wallpaper directory render. Older unmarked choices
  stay hidden until restaged and the save is acknowledged.
- A save failure restores the previous wallpaper. Copies survive mode changes, failed
  saves, disable and removal, and Station evicts no cache.
