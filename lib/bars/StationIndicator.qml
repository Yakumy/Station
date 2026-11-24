import QtQuick
import "." as Bars

// The indicator as a widget of its own on Station's bar. `port` is the logo widget's
// (StationPanel.indicator), so one widget per bar reads the service.
Bars.StationBar {
  id: root

  property var port: null
  property string moduleName: ""
  property var settings: ({})

  part: "indicator"
  visible: !!port
  stationNumber: port ? port.stationNumber : 1
  compactMode: port ? port.compactMode : "on"
  showOpenApps: !!port && port.showOpenApps
  stationApps: port ? port.stationApps : ({})
  workspaceMap: port ? port.workspaceMap : null
  workspaceApps: port ? port.workspaceApps : ({})
  indicatorStyle: port ? port.indicatorStyle : "prefixed"
  onStationSelected: function(number) { if (port) port.select(number, root.screenName) }
}
