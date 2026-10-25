# README media

These GIFs are local, silent, looping assets. They do not depend on an external
image host.

| File | Source | Presentation |
| --- | --- | --- |
| `stations.gif` | Existing Station launch animation, 3.3–8.6 seconds | Illustrated workspace-switching tour, not a hardware recording. |
| `wallpaper.gif` | Existing Station launch animation, 46.3–51.6 seconds | Illustrated wallpaper framing; the README separately shows the actual editor. |
| `bars.gif` | Current `BarTab.qml`, installed Omarchy components and theme | Isolated preview data cycles through edges, sizes, backgrounds, and styles. No desktop config writes. |

The first two excerpts come from the local project export
`videos/intro/out/station-2.1.7-launch-v4.mp4`. That earlier release's promotional
video and source project are ignored by Git; the extracted GIFs are checked in.
They illustrate features that remain available, rather than claiming to show
the latest panel chrome or verified three-monitor hardware. Audio is omitted.
The footer is cropped out to avoid presenting the earlier version as current.

## Export settings

The video excerpts use this filter, with `-ss 3.3` or `-ss 46.3`, `-t 5.3`,
`-an`, and `-loop 0`:

```text
[0:v]crop=1920:1000:0:0,fps=10,scale=960:-1:flags=lanczos,split[a][b];
[a]palettegen=max_colors=96[p];
[b][p]paletteuse=dither=bayer:bayer_scale=3
```

To recreate the Bar frames from the repository, with access to a Wayland session:

```bash
STATION_README_TOUR=1 python3 tools/v2/check-bar-tab.py /tmp/station-readme-bar
ffmpeg -framerate 5 -i /tmp/station-readme-bar/frame-%03d.png \
  -filter_complex '[0:v]scale=960:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer:bayer_scale=3' \
  -loop 0 docs/assets/tours/bars.gif
```

The optional tour mode opens a temporary preview window and captures only the
fixed-size Bar tab content. The usual `check-bar-tab.py` mode continues to test
monitor-selection dropdown bindings and save one screenshot.
