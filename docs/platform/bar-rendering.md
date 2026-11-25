<!-- summary: Content zoom, blurry text and images, the Station mark's tint, size and alignment. -->
<!-- code: lib/bars/omarchy/** lib/bars/Station* -->
# Bar text, image and logo rendering

Dated sections are investigations, oldest first. A later one can supersede an earlier one.

## Station logo in the bar

**[LIVE][SRC] Bar-logo tint:** a captured Miasma bar showed fully covered
Omarchy-logo and `[S1]` pixels at the requested `#c2c2b0`, while Station's
fully covered pixels were `#979789`. No QML opacity was applied. Qt
`MultiEffect` colorization was multiplying the tint by the beige SVG stroke's
luminance. The SVG is now a white, fully opaque alpha mask; its visible color
continues to come exclusively from `WidgetButton.foreground`. A fresh live bar
capture after installation contains exact `#c2c2b0` pixels in the Station mark
and no pixels at the former `#979789` peak.

**[LIVE][SRC] Bar-logo optical size:** the SVG has no unused outer margin: its
stroked path reaches all four view-box edges, and the live 10px Station mark
painted a 10×10 bound versus roughly 8×9 for the Omarchy font glyph. The
perceived smaller size came from ink density instead: normalized screenshot
coverage was 41.69 equivalent full pixels for Station versus 44.41 for
Omarchy. Increasing the source stroke from 50 to 54 restores comparable visual
weight while retaining the same `Style.font.body` size and bar-slot geometry.
The installed result measured 44.28 equivalent full-color pixels versus 44.41
for Omarchy (about 0.3% apart), while preserving the exact bar foreground.
The user's visual follow-up preferred a slightly larger mark, so its frame is
now one theme-scaled pixel larger (11×11 with the current font setting). A live
capture also showed `[S1]` at y=5…14 while both marks occupied y=6…15; Station
translates that label down by `Style.space(1)` to align their painted bounds.
After installation, the current capture scale painted Omarchy at 20×20 and
Station at 22×22 physical pixels with the same 21.5 vertical center; `[S1]`
centered at 22.0, within half a physical pixel of both marks.

**[SRC][QTTEST] 2.1.9 bar geometry revision (2026-10-22):** the preceding
optical enlargement and fixed label translation are superseded. `StationBar.qml`
measures the menu glyph with `TextMetrics`, uses its ink height for the mark,
and aligns the unbracketed `S1` label by its ink bounds. The horizontal gap
matches the menu-to-mark gap, including the host's rounded label origin.
`Grid` stacks the two existing buttons on left/right bars and reports their
combined height; the previous unconditional `Row` put the indicator outside
the vertical bar's fixed width. An isolated Qt harness using the installed
`WidgetButton` checks all four positions, fonts 10/12/18, S1/S10, and both click
targets. Final live rendering and bar-rebuild behavior await user acceptance.

## Bar content zoom rendering repair (2026-10-25)

- [SRC][DOC] Installed `Ui.WidgetButton` and `Ui.OpticalGlyph` use
  `Text.NativeRendering`. Qt documents pixelated results when transforming that
  renderer: https://doc.qt.io/qt-6/qml-qtquick-text.html#renderType-prop.
  The previous larger-loader-texture fix left that renderer unchanged; the user
  reported that the enlarged clock and indicator glyphs were still blurry.
- [SRC] Zoomed module subtrees now switch native text (including icon fonts) to
  `Text.QtRendering` and omit the loader layer. Image source-size enlargement
  remains in place. Default-size modules restore their original rendering mode;
  Station's directly sized widget remains exempt from subtree zoom.
- [QTTEST] `python3 test/qml/bar-rendering.py` exercises the production
  traversal with real Qt Text/Image objects: fractional and integer zoom,
  nested glyphs, repeated scans, newly added/destroyed text, and restoration.
  Passed on Qt 6.12.0. This verifies rendering policy, not final desktop pixels;
  installed-bar visual acceptance remains pending.

## Bar geometry follow-up (2026-10-25)

- [LIVE][SRC] After the scalable-rendering repair, the user confirmed enlarged
  glyphs were sharp. Their screenshots also showed that Station's logo-to-label
  gap grew less than neighboring widget gaps and that the right Pill island
  included the tray's invisible collapsed drawer reserve.
- [SRC] Station now uses the host button margin on both sides of both internal
  controls and enters the same uniform subtree zoom path as other widgets. The
  tray slot subtracts `drawerExtent - revealExtent` from its flow footprint, so
  the Pill follows the chevron while collapsed and grows as icons reveal. This
  applies only to Omarchy 4.0's tray; see the 2026-11-16 tray note.
- [SRC][QTTEST] Bar height is capped at 5% of the monitor mode's shorter native
  side. Each live bar reports a content-size maximum that preserves
  `Style.spacing.sm` on both cross-axis edges and checks the fully revealed
  left, centered, and right regions along the bar. Model tests cover both
  limiting axes and tray reveal extents. The offscreen layout harness covers
  all four preview sides. The follow-up below revises the label placement and
  repairs the runtime publication of the maximum.

- [LIVE][SRC] The installed shell logged `ReferenceError: barContent is not
  defined` at MonitorBar's root maximum binding: the id belongs to the nested
  BarPanel component. The content limit now publishes to a root measurement
  property on completion and change, matching the minimum-length path.
  The runtime Qt harness exercises that component boundary and verifies that
  content zoom follows requests and changing limits.
- [SRC][QTTEST] Preview edge gaps return to `Style.spacing.sm`. Names move
  toward the card center and reserve the maximum preview thickness plus a
  theme gap on every side. The layout test uses an oversized saved height to
  verify clamping and label separation on all four sides.

## Enlarged image layers (2026-10-25)

- [SRC] StationMark's tint source and Omarchy Tray's symbolic image sources
  use `layer.enabled`; the tray drawer also layers its Row/Column. Increasing
  image `sourceSize` alone leaves these intermediate textures at baseline size.
  MonitorBar now scales existing layer textures too, including the output pixel
  ratio, while leaving Loader layers disabled and preserving scalable text.
- [QTTEST] `check-bar-rendering.py` checks nested/default/explicit layer sizes,
  geometry updates, repeated zoom and restoration. `check-bar-icons.py` uses
  Wayland/GPU rendering of the real logo SVG through MultiEffect and a nested
  group layer at 3x. Compared with a directly sized reference, the corrected
  render has less than one quarter of the original summed red-channel pixel
  error. The capture visibly resolves the logo edges. This does not establish
  the quality of every application's supplied tray bitmap.

## Station logo follow-up (2026-10-25)

- [LIVE] The user still observed a soft Station bar logo after the intermediate
  layer fix. The previous GPU fixture recreated the image/effect structure; it
  did not instantiate StationMark and was insufficient evidence for that logo.
- [SRC] StationMark now renders its SVG paths with Shape.CurveRenderer and
  direct theme tint, eliminating its image/effect rasterization path. Tray
  image and group-layer handling remains in place. StationBar positions the
  mark from the actual centered Text baseline used by WidgetButton rather
  than reconstructing it from rounded FontMetrics height.
- [QTTEST] The GPU check now instantiates the production StationMark at 3x
  and compares it with a directly sized production mark. The captured edges
  are sharp. The layout harness passes 216 combinations covering three font
  sizes, three bar heights, three zooms, four edges and S1/S10. These checks
  do not substitute for the user's final desktop confirmation.

## Confirmed logo correction and global bar controls (2026-10-25)

- [LIVE] The user confirmed the vector Station logo is now sharp and aligned.
  The problem was rasterization of the image/tint path before content zoom;
  enlarging decoded images and intermediate textures did not reliably fix the
  production logo. Rendering the original paths directly with CurveRenderer
  removes that raster boundary. A centered Text reference also removes the
  vertical discrepancy from reconstructing WidgetButton's baseline with
  rounded FontMetrics values.
- [SRC] Omarchy's Bar → Position menu runs `omarchy bar position`, which
  writes global `bar.position`. Stock bar dragging writes the same setting.
  Station's per-monitor overrides previously masked global changes; its drag
  adaptation wrote only shell.json monitor rows while config.bars remained the
  authority. The service now observes global edge changes and updates every
  saved/connected monitor, preserving presence and appearance. Drag completion
  calls the allowlisted global action. Station's card arrows remain per-monitor.
- [QTTEST] Production-function tests cover four global edges, saved/disconnected
  entries, appearance preservation, initial attachment without override loss,
  pending publication during an open panel, and drag-to-service dispatch.

- [LIVE] Stock `omarchy bar position right|bottom|left|top` updated both saved
  monitor edges in the installed service. Each command was allowed to finish
  its asynchronous shell/config writes before the next command; issuing the
  next command immediately after observing config.json can race the previous
  shell.json mirror write. Original bar settings were backed up and restored,
  followed by shell restart/ping. Physical pointer dragging remains a manual
  check; the automated drag test verifies the completion-to-service path.

## Intermittent clock blur and rapid switching (2026-10-27)

- [SRC][QTTEST] The installed clock's vertical `Repeater` replaces its native
  text delegates on minute/format changes. Equal-sized replacements do not
  trigger MonitorBar's geometry-based rendering rescan. The clock now schedules
  a rescan on `displayTextChanged`, after delegate replacement settles.
  `check-bar-rendering.py` changes equal-sized clock lines twice: the new test
  fails on the old rendering policy and passes with the notification hook.
- [LIVE] On the installed pre-repair code (18982f9), simultaneous numbered IPC
  requests returned `busy` for two of three requests. [SRC] A return to an
  occupied station can therefore be dropped while another switch is running.
  The service now retains the latest numbered target, cancels it on generation
  changes, and checks Lua response text before recording a successful switch.
  This is a demonstrated lost-request defect, not proof that it explains every
  reported missing-window incident.
- [LIVE] Slow S1→S2→S3→S1 switching preserved the surviving clients' workspace
  IDs. A disposable terminal moved right twice and left twice across the
  rotated eDP/HDMI arrangement, including station boundaries, through the
  installed `shiftWindow` IPC. The registered default is Super+Ctrl+Shift+Arrow;
  Ctrl+Shift+Arrow alone is not a Station binding. A physical keypress has not
  been tested by the agent.
- [SRC] Delayed bar property injection now stops if its bar root has already
  been destroyed; the session journal contained this teardown exception.
- Verification: 190 Node tests, 5 rendering Qt checks, 23 layout Qt checks,
  theme-token scan, and Wayland component compilation passed. The layout
  fixture emits existing missing-token warnings against Omarchy 4.0.6.
  Node's spawned Lua processes time out in the sandbox (including `print(123)`);
  the complete suite passes with session access. Plugin validation passed on
  a clean tracked-tree export containing the changed runtime files; validation
  of the source directory encounters ignored video `node_modules` symlinks.
  Live snapshots and probe scripts are under `/tmp/station-20261027-before`
  and `/tmp/station-*-probe.py`, not committed.
