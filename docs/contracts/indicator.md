<!-- summary: How fresh the bar's station number is, indicator styles, Compact mode, app icons, drawer. -->
<!-- code: lib/stations/OpenApp* lib/bars/Station* lib/panel/Service* -->
# Station indicator and open apps

## Station indicator freshness

The bar reads the station from the workspace Quickshell reports for the compositor,
not from the service's last confirmed switch: Station mode follows the focused output,
and Repetitive and Non-repetitive follow their own output. A native workspace change
(`SUPER+Tab`, scroll, or another indicator) then repaints with the compositor event
instead of waiting for follow focus and the station batch. A special, named or
out-of-map workspace keeps the confirmed station. The service still changes
`currentStation` only after its compositor batch succeeds, so the saved station never
predicts a switch.

A replacement-bar widget also samples the confirmed scalar every 50 ms through a
detached bridge read, as the fallback above. It does not copy the app lists or panel
snapshot at that rate. Full snapshots retain their 150 ms open/listed and 1 s closed
Compact On cadence. The trusted direct-service path stays reactive, with no polling. A
retired publisher returns no station number.

## Open apps

The Workspaces tab sets the indicator count (`stationCount`, 1 to 10, default 3),
`compactMode` and `showOpenApps`, and the indicator style as `indicatorStyle`: `prefixed` (S1, or W1 outside Station mode), `number`, `roman`, or
`kanji` (the 一 to 十 numerals bjarneo's kanji-workspaces widget uses, drawn in the bar
font through fontconfig's CJK fallback; a workspace above ten keeps its number).
A saved `dots` style, which did not fit the compact modes, loads as `prefixed`. `compactMode` is Off (`off`), On hover (`hover`, the default) or On (`on`).
`showOpenApps` (default on) adds app icons in Off and On hover; On shows none. With open
apps off, the numbers use Omarchy's own workspace gap: one spacing step between columns
and two between rows, with no gap left behind for the hidden app column. The old
`stationAppsMode` loads as Always on → Off, On hover → On hover, Off → On without apps.

In Station mode every bar shows the focused output's station. In Repetitive and
Non-repetitive each bar shows its own output: its own numbers, the one it shows and the
apps on them, and a click shows that number on that output. It reads the shown
workspace from Quickshell's monitor and refreshes it on workspace events, because
Omarchy's indicator, which would otherwise refresh it, is usually hidden.

- Off lists every available number with no chevron. Whenever every number is visible —
  Off, or On hover while the drawer is open — Omarchy's tiling square glyph (U+F14FB),
  drawn by `WidgetButton` at Omarchy's icon size, stands for the current one, whatever
  the indicator style, as in Omarchy's indicator.
- As in Omarchy's indicator, a number that is not shown and has no window is drawn at
  half opacity, so the current one reads as active.
- On hover shows the current number and a chevron, and reveals the rest, with one icon
  per mapped window when apps are on. It uses the stock tray's 600 ms OutCubic motion,
  and the current label stays opaque.
- On shows only the current number, and its compositor feed stops.
- Clipped labels and icons accept no clicks until fully open, so the logo always opens
  the panel.
- Labels and icons switch the whole station. Scratchpads are excluded. A pinned window
  appears once at its home station.
- The feed uses the saved map, including the numbers each monitor owns in
  Non-repetitive, and a pending journal's identities take precedence.
- Icons keep original colors and full opacity, regardless of focus.
