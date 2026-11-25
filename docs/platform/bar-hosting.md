<!-- summary: What the host gives plugin widgets: bar api, tray sizing, service lookup, clipping and hover, panel hotkeys. -->
<!-- code: lib/bars/omarchy/** Bar.qml -->
# Hosting plugin widgets on a replacement bar

Dated sections are investigations, oldest first. A later one can supersede an earlier one.

## Plugin bar api without center-reveal properties (2026-11-16)

- **[INFER]** GitHub issue #10 reports that on Omarchy `4.0.0.r7840.gac6cb9c-1`,
  `PluginBarApi.qml` no longer declares `centerSectionRevealHeld` or
  `_centerHoverRevealSuppressed`. Assigning an undeclared QML property throws, so
  `bindPluginBarApi()` stopped before `syncPluginBarApiObjects()` and third-party
  widgets got no click targets. Station did not run that build.
- **[SRC]** The 4.0.6 and 4.5.0-3 packages still declare both properties.
- **[SRC]** Station now assigns each optional api property only when the api declares
  it, as it already did for the tray-section properties. `bar-per-monitor.test.cjs`
  runs the production functions in Node against a fake api that throws on an
  undeclared property, with and without the two properties.

## Tray sizing in Omarchy 4.5 (2026-11-16)

- **[SRC]** GitHub issue #11. In the 4.0.6 package, `Tray.qml` sizes its horizontal
  root as `pinnedWidth + chevron + drawerExtent`, reserving the hidden drawer. In
  4.5.0-3 it is `pinnedRow + chevronWidth + revealExtent`: the drawer opens between
  the pinned icons and the chevron and only the revealed part counts. Subtracting the
  hidden part again made a collapsed tray's slot negative, clamped to zero, and moved
  its content out of view, so the tray could not be hovered.
- **[SRC]** The 4.5 tray adds `fixedAtStart`, `sectionShown`, `hasDrawer` and other
  root properties with that layout; 4.0.6 has none of them. Station treats a tray
  without `fixedAtStart` as reserving its drawer and leaves any other tray's length and
  position as the tray reports them.
- **[QTTEST]** `bar-tray-reserve` runs the production slot bindings against doubles of
  both tray shapes, horizontal and vertical, collapsed to fully revealed.
- **[INFER]** The tray on the maintainer's 4.5.0-3 desktop is expected to show again
  after the update; the installed bar is the check.

## Third-party widget services (2026-11-21)

- **[SRC]** GitHub issue #23. In the installed `/usr/share/omarchy/shell/shell.qml`
  and in upstream `omacom/omarchy` `shell/shell.qml`, `pluginShellForBarEntry()`
  creates its `PluginShellApi` without `_serviceLookup`, so `serviceFor()` returns
  null. A full-bar plugin's own facade has no `pluginShellForId()`, and its
  `serviceFor()` answers only for its own id. Station has no way to hand a hosted
  widget that widget's service.
- **[SRC]** The reporter's `ssupt.audio-control` disables its sliders, mute and wheel
  when its service is null. The same widget works under Omarchy's bar, which calls
  `pluginShellForId()` on the shell root.
- **[SRC]** Omarchy's bar finds click targets with `Util.itemContainsPoint`, which
  honours clipping and ancestor visibility. Station compared the target's rectangle
  only, so a collapsed tray drawer's icons, laid out past its clipped edge, could take
  a click meant for a visible icon. `bar-click-target.test.cjs` covers the port.
- **[QTTEST]** A `qmltestrunner` probe on Qt 6.12: an inner `MouseArea` with `onWheel`
  under a full-size left-button `MouseArea` with no wheel handler, as in Station's
  slot, received the wheel. Forwarding the wheel as well would deliver every step
  twice, so Station does not. This was a probe of Qt's delivery, not of the production
  bar.
- **[SRC]** Upstream already tracks the facade: omacom/omarchy#13289 (with #11051,
  #11796 and #12648) and the open fix omacom/omarchy#13471, which gives
  `pluginShellForBarEntry()` an own-service-only `_serviceLookup`. Upstream `master`
  `shell/shell.qml` (last changed 2026-11-16) still lacks it. Station issue #23 stays
  open until that lands; Station needs no change for it.
- **[SRC]** 2026-11-25: the installed Omarchy and upstream's default branch `quattro` still
  lack the lookup, and omacom/omarchy#13194 and #13471 are still open.
- **[QTTEST]** GitHub PR #29. An offscreen Qt 6.12 probe of the service and widget in
  [Widget services](../widget-services.md) with Station's `BarBridge.js`: the action and the
  state reached two widgets whose lookup was null, a service that started after its
  widgets, and one that replaced another. A widget whose lookup worked used it. This was a
  probe of the pattern, not of a plugin in the live shell.

## Indicator hover past a clipped slot (2026-11-21)

- **[SRC]** GitHub PR #21. Omarchy's `Indicators.qml` puts its `hiddenBlockZone`
  `HoverHandler` past the widget's own edge, by the length of the inactive icons. With
  no active indicator the widget is 0 px wide, so that zone is the only hover target.
  Omarchy's `Bar.qml` clips a slot's widget area only while dragging or removing.
- **[QTTEST]** A `qmltestrunner` probe on Qt 6.12: a `HoverHandler` on a child reaching
  past a 0-wide parent never reported `hovered` when the parent clipped, and did when
  it did not. Station's slot clipped always, so the inactive indicators never revealed.
  This was a probe of Qt's delivery, not of the production bar.
- **[SRC]** Station's slot now clips only while dragged or while it holds the old
  tray's reserved drawer, so the #23 drawer case keeps its clip.

## Bar panel hotkeys under a replacement bar (2026-11-22)

- **[SRC]** Omarchy's `default/hypr/bindings/utilities.lua` binds SUPER + CTRL +
  `code:10` to `code:18` ("Bar panel 1" to 9) to
  `omarchy-shell -q shell togglePanelAt right N`. `shell.qml` `togglePanelAt` calls
  `shell.bar.panelWidgetIdAt(section, index)` and returns `unknown` when the active
  bar lacks it. `shell.bar` is the full-bar plugin's root, Station's `Bar.qml`, not
  the per-monitor `MonitorBar.qml` that held the function.
- **[LIVE]** With Station's bar active, `omarchy-shell shell togglePanelAt right 1`
  answered `unknown` and the hotkeys opened nothing. `Bar.qml` now forwards the call
  to the focused monitor's bar.
