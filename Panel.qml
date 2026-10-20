import "lib" as Station
import "lib/BarBridge.js" as BarBridge

Station.StationPanel {
  // Import beside Service.qml: Quickshell rewrites nested QML type imports to
  // qs:/// URLs, which would create a second .pragma library instance here.
  bridgeCurrent: function() { return BarBridge.current() }
}
