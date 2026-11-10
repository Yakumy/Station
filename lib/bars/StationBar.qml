import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Ui as Ui
import qs.Commons
import qs.Commons as Commons
import "../panel" as PanelUi
import "../stations/Grid.js" as Grid

Item {
  id: root
  property var bar: null
  property int stationNumber: 1
  property var stationApps: ({})
  property string appsMode: "hover"
  // Repetitive and Non-repetitive show this bar's output: its own numbers, the one
  // it shows, and its apps. Station mode shows the station, the same on every bar.
  property var workspaceMap: null
  property var workspaceApps: ({})
  property string indicatorStyle: "prefixed"
  readonly property var hyprMonitor: {
    var window = root.QsWindow.window
    var screen = window ? window.screen : null
    return screen ? Hyprland.monitorFor(screen) : null
  }
  readonly property string screenName: hyprMonitor ? String(hyprMonitor.name || "") : ""
  readonly property int outputIndex: workspaceMap && Array.isArray(workspaceMap.outputs)
    ? workspaceMap.outputs.indexOf(screenName) : -1
  readonly property bool perOutput: Grid.mode(workspaceMap) !== "station" && outputIndex !== -1
  readonly property var ownNumbers: perOutput ? Grid.numbers(workspaceMap, outputIndex) : []
  readonly property int activeWorkspaceId: hyprMonitor && hyprMonitor.activeWorkspace ? hyprMonitor.activeWorkspace.id : -1
  readonly property int shownNumber: perOutput
    ? (Grid.station(activeWorkspaceId, workspaceMap) || ownNumbers[0] || 1) : stationNumber
  readonly property var groupApps: perOutput ? (workspaceApps[screenName] || ({})) : stationApps
  function labelFor(number) {
    if (indicatorStyle === "number") return String(number)
    if (indicatorStyle === "dots") return number === shownNumber ? "\u25cf" : "\u25cb"
    if (indicatorStyle === "roman") return ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"][number - 1] || String(number)
    return (perOutput ? "W" : "S") + number
  }
  // Nothing else refreshes per-monitor workspaces while Omarchy's indicator is
  // hidden. Quickshell credits a switch to the focused monitor only.
  Connections {
    target: Hyprland
    enabled: root.perOutput
    function onRawEvent(event) {
      var name = event ? String(event.name) : ""
      if (name === "workspacev2" || name === "moveworkspacev2" || name === "focusedmon"
          || name === "changeworkspaceid" || name === "monitoraddedv2" || name === "monitorremovedv2")
        Hyprland.refreshMonitors()
    }
  }
  property bool expanded: false
  property bool opened: false
  property alias anchorItem: logoButton
  signal pressed()
  signal stationSelected(int number)
  readonly property bool vertical: bar ? bar.vertical : false
  readonly property bool showApps: appsMode !== "hide"
  readonly property bool alwaysOpen: appsMode === "always"
  readonly property bool showExpander: appsMode === "hover"
  readonly property real barSize: bar ? bar.barSize : Style.bar.sizeHorizontal
  readonly property real contentFontSize: Style.font.body
  readonly property real rasterZoom: bar && "effectiveContentSize" in bar
    ? Math.max(1, Number(bar.effectiveContentSize) / Math.max(1, Math.ceil(Style.font.body))) : 1
  // Match Omarchy's status controls structurally: one iconSlot per control,
  // with zero spacing between slots in both orientations.
  readonly property real primarySlot: Style.bar.iconSlot
  readonly property real mainGap: 0
  readonly property real stationGap: Style.spacing.xl
  readonly property real labelGap: Style.spacing.xxs
  readonly property real appGap: Style.spacing.sm
  readonly property rect menuInk: menuTextMetrics.tightBoundingRect
  readonly property real logoSize: menuInk.height
  readonly property real inkCenter: menuReference.y + menuReference.baselineOffset + menuInk.y + logoSize / 2
  readonly property rect indicatorInk: indicatorMetrics.tightBoundingRect("S" + stationNumber)
  // Follow the painted station-label guide: its height limits horizontal bars,
  // and its width limits vertical bars.
  readonly property real appSize: vertical ? indicatorInk.width : indicatorInk.height
  readonly property var stations: {
    var numbers = Object.keys(groupApps || {}).map(Number)
    ownNumbers.forEach(function(number) { if (numbers.indexOf(number) === -1) numbers.push(number) })
    if (numbers.indexOf(shownNumber) === -1) numbers.push(shownNumber)
    return numbers.sort(function(a, b) { return a - b })
  }
  property int groupsRevision: 0
  readonly property var currentGroup: {
    var revision = groupsRevision
    return stationGroups.itemAt(stations.indexOf(shownNumber))
  }
  readonly property real currentOffset: currentGroup ? (vertical ? currentGroup.y : currentGroup.x) : 0
  property real revealProgress: showApps && (alwaysOpen || expanded) ? 1 : 0
  readonly property real collapsedExtent: primarySlot
  readonly property real fullExtent: vertical ? groups.implicitHeight : groups.implicitWidth
  readonly property real revealExtent: collapsedExtent + Math.max(0, fullExtent - collapsedExtent) * revealProgress
  readonly property real logoExtent: primarySlot
  readonly property real arrowExtent: primarySlot
  readonly property real leadingInset: 0
  readonly property real length: leadingInset + logoExtent + mainGap + revealExtent + (showExpander ? mainGap + arrowExtent : 0)
  implicitWidth: vertical ? barSize : length
  implicitHeight: vertical ? length : barSize
  onAppsModeChanged: if (appsMode !== "hover") expanded = false
  Behavior on revealProgress {
    // Exact stock tray drawer timing, including closing and interrupted motion.
    NumberAnimation { duration: 600; easing.type: Easing.OutCubic }
  }
  FontMetrics { id: menuMetrics; font.family: "omarchy"; font.pixelSize: root.contentFontSize }
  TextMetrics { id: menuTextMetrics; font: menuMetrics.font; text: "\ue900" }
  FontMetrics { id: indicatorMetrics; font.family: root.bar ? root.bar.fontFamily : Style.font.family; font.pixelSize: root.contentFontSize }
  TextMetrics { id: arrowMetrics; font.family: indicatorMetrics.font.family; font.pixelSize: root.contentFontSize; text: "\uf054" }

  Ui.WidgetButton {
    id: logoButton
    x: root.vertical ? 0 : root.leadingInset
    y: root.vertical ? root.leadingInset : 0
    bar: root.bar
    text: "Station"
    tooltipText: "Station"
    labelVisible: false
    hasVisualContent: true
    fixedWidth: root.vertical ? root.barSize : root.primarySlot
    fixedHeight: root.vertical ? root.primarySlot : root.barSize
    onPressed: root.pressed()
    Text { id: menuReference; anchors.centerIn: parent; visible: false; text: "\ue900"; font: menuMetrics.font }
    PanelUi.StationMark {
      width: root.logoSize; height: width
      x: (parent.width - width) / 2
      y: root.inkCenter - height / 2
      tint: logoButton.foreground
    }
    Rectangle {
      visible: root.opened
      width: root.vertical ? Math.max(1, Style.space(2)) : parent.width
      height: root.vertical ? parent.height : Math.max(1, Style.space(2))
      x: root.vertical && root.bar.position === "right" ? 0 : parent.width - width
      y: root.vertical ? 0 : parent.height - height
      color: Commons.Color.accent
      radius: Style.cornerRadius
    }
  }

  Item {
    id: drawer
    objectName: "stationDrawer"
    x: root.vertical ? 0 : root.leadingInset + root.logoExtent + root.mainGap
    y: root.vertical ? root.leadingInset + root.logoExtent + root.mainGap : 0
    width: root.vertical ? root.barSize : root.revealExtent + (root.showExpander ? root.mainGap + root.arrowExtent : 0)
    height: root.vertical ? root.revealExtent + (root.showExpander ? root.mainGap + root.arrowExtent : 0) : root.barSize
    HoverHandler { onHoveredChanged: root.expanded = hovered && root.appsMode === "hover" }
    Item {
      id: viewport
      width: root.vertical ? root.barSize : root.revealExtent
      height: root.vertical ? root.revealExtent : root.barSize
      clip: true
      Grid {
        id: groups
        columns: root.vertical ? 1 : Math.max(1, root.stations.length)
        spacing: root.stationGap
        // Keep the current label mounted and opaque. Its natural position is
        // revealed as the preceding station groups slide out from behind it.
        x: root.vertical ? 0 : -root.currentOffset * (1 - root.revealProgress)
        y: root.vertical ? -root.currentOffset * (1 - root.revealProgress) : 0
        Repeater {
          id: stationGroups
          onItemAdded: root.groupsRevision++
          onItemRemoved: root.groupsRevision++
          model: root.stations
          delegate: Grid {
            id: group
            objectName: "stationGroup-" + modelData
            required property int modelData
            readonly property var apps: root.groupApps[modelData] || []
            columns: root.vertical ? 1 : 2
            spacing: root.labelGap
            Ui.WidgetButton {
              id: stationButton
              objectName: "stationLabel-" + group.modelData
              bar: root.bar
              text: root.labelFor(group.modelData)
              opacity: group.modelData === root.shownNumber ? 1 : root.revealProgress
              Behavior on opacity { enabled: false }
              // MonitorBar routes module clicks through its own registered-target
              // hit test, which cannot see this drawer viewport's clip. A hidden
              // preceding station may otherwise extend left over the logo while
              // the current station is translated into the collapsed position.
              interactive: group.modelData === root.shownNumber || root.revealProgress > 0.99
              tooltipText: (root.perOutput ? "Workspace " : "Station ") + group.modelData
              labelVisible: false; hasVisualContent: true
              fixedWidth: root.vertical ? root.barSize : root.primarySlot
              fixedHeight: root.vertical ? root.primarySlot : root.barSize
              onPressed: root.stationSelected(group.modelData)
              Text {
                id: stationLabel
                text: stationButton.text; font: indicatorMetrics.font; color: stationButton.foreground
                x: (parent.width - indicatorMetrics.tightBoundingRect(text).width) / 2
                  - indicatorMetrics.tightBoundingRect(text).x
                y: root.inkCenter - indicatorMetrics.tightBoundingRect(text).height / 2 - indicatorMetrics.ascent - indicatorMetrics.tightBoundingRect(text).y
              }
            }
            Grid {
              visible: group.apps.length > 0
              opacity: root.revealProgress
              columns: root.vertical ? 1 : Math.max(1, group.apps.length)
              spacing: root.appGap
              Repeater {
                model: group.apps
                delegate: Ui.WidgetButton {
                  id: appButton
                  objectName: "stationApp-" + modelData.address
                  required property var modelData
                  bar: root.bar
                  text: modelData.title
                  tooltipText: (root.perOutput ? "Workspace " : "Station ") + group.modelData + ": " + modelData.title
                  // App targets are meaningful only after the drawer has reached
                  // its open geometry. This also keeps clipped targets from
                  // intercepting the logo during opening and closing.
                  interactive: root.revealProgress > 0.99
                  labelVisible: false; hasVisualContent: true
                  fixedWidth: root.vertical ? root.barSize : root.appSize
                  fixedHeight: root.vertical ? root.appSize : root.barSize
                  onPressed: root.stationSelected(group.modelData)
                  readonly property var entry: {
                    var entries = DesktopEntries.applications.values
                    return DesktopEntries.heuristicLookup(modelData.appId) || DesktopEntries.heuristicLookup(modelData.initialAppId)
                  }
                  Image {
                    id: appImage
                    width: root.appSize; height: width
                    x: (parent.width - width) / 2
                    y: root.vertical ? 0 : root.inkCenter - height / 2
                    readonly property bool stationRasterManaged: true
                    readonly property int rasterPixels: Math.max(1,
                      Math.ceil(width * Screen.devicePixelRatio * root.rasterZoom))
                    // Decode above the final physical size and mipmap down;
                    // render directly, without an intermediate effect texture.
                    sourceSize: Qt.size(Math.max(64, rasterPixels * 2), Math.max(64, rasterPixels * 2))
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                    source: (appButton.entry && appButton.entry.icon ? Quickshell.iconPath(appButton.entry.icon, true) : "")
                      || Quickshell.iconPath("application-x-executable", true)
                  }
                  Text {
                    anchors.centerIn: appImage
                    visible: appImage.status === Image.Error || appImage.source.toString() === ""
                    text: "□"; font: indicatorMetrics.font; color: appButton.foreground
                  }
                }
              }
            }
          }
        }
      }
    }
    Ui.WidgetButton {
      bar: root.bar
      visible: root.showExpander
      text: "\uf054"
      labelVisible: false; hasVisualContent: true
      objectName: "stationExpander"
      tooltipText: "Stations and open apps"
      x: root.vertical ? 0 : root.revealExtent + root.mainGap
      y: root.vertical ? root.revealExtent + root.mainGap : 0
      fixedWidth: root.vertical ? root.barSize : root.primarySlot
      fixedHeight: root.vertical ? root.primarySlot : root.barSize
      onPressed: root.expanded = !root.expanded
      Text {
        text: parent.text; font: indicatorMetrics.font; color: parent.foreground
        x: (parent.width - arrowMetrics.tightBoundingRect.width) / 2 - arrowMetrics.tightBoundingRect.x
        y: root.inkCenter - arrowMetrics.tightBoundingRect.height / 2 - indicatorMetrics.ascent - arrowMetrics.tightBoundingRect.y
        rotation: root.vertical ? 90 : 0
      }
    }
  }
}
