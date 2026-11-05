import "lib/panel" as PanelUi
import "lib/BarBridge.js" as BarBridge

PanelUi.StationPanel {
  // Import beside Service.qml: Quickshell rewrites nested QML type imports to
  // qs:/// URLs, which would create a second .pragma library instance here.
  bridgeCurrent: function() { return BarBridge.current() }
}
