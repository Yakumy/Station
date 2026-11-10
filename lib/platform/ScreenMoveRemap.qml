import QtQuick

// Station's copy of the host's former Ui.ScreenMoveRemap. Omarchy removed that
// type from qs.Ui on 2026-11-01 (basecamp/omarchy#17229), so importing it from
// the host stops the bar and the wallpaper service loading on newer builds.
//
// Hyprland before 0.57 leaves an already-mapped layer surface at its old global
// position when its monitor moves within the layout, so long-lived surfaces
// such as the bar and the wallpaper keep rendering at the old offset until they
// are unmapped and remapped. Watch the screen's origin and pulse `remapping`
// when it moves; the owning window folds that into its `visible` binding so the
// compositor re-places the surface at the monitor's new origin.
Item {
  id: root

  required property var window
  readonly property var screen: window ? window.screen : null

  // Fold into the window's binding: visible: <shown> && !guard.remapping
  property bool remapping: false

  visible: false

  // A layout reshuffle can move the monitor more than once before it lands.
  // Let the positions settle before the single remap pulse.
  Timer {
    id: settleTimer
    interval: 200
    onTriggered: root.remapping = true
  }

  // Hold the surface unmapped for a beat so the compositor processes the
  // unmap before the remap instead of coalescing them into a no-op.
  Timer {
    interval: 50
    running: root.remapping
    onTriggered: root.remapping = false
  }

  Connections {
    target: root.screen
    function onXChanged() { settleTimer.restart() }
    function onYChanged() { settleTimer.restart() }
  }
}
