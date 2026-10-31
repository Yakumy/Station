import QtQuick
import Quickshell
import qs.Ui as Ui
import qs.Commons
import qs.Commons as Commons
import "." as Station

Item {
  id: root
  property var bar: null
  property int stationNumber: 1
  property var stationApps: ({})
  property bool showApps: true
  property bool expanded: false
  property bool opened: false
  property alias anchorItem: logoButton
  signal pressed()
  signal stationSelected(int number)
  readonly property bool vertical: bar ? bar.vertical : false
  readonly property real barSize: bar ? bar.barSize : Style.bar.sizeHorizontal
  readonly property real contentFontSize: Style.font.body
  readonly property real rasterZoom: bar && "effectiveContentSize" in bar
    ? Math.max(1, Number(bar.effectiveContentSize) / Math.max(1, Math.ceil(Style.font.body))) : 1
  // All distances scale once with the theme, then uniformly with host content zoom.
  readonly property real mainGap: Style.spaceReal(22)
  readonly property real stationGap: Style.spacing.xxl
  readonly property real labelGap: Style.spacing.lg
  readonly property real appGap: Style.spacing.sm
  readonly property rect menuInk: menuTextMetrics.tightBoundingRect
  readonly property real logoSize: menuInk.height
  readonly property real inkCenter: menuReference.y + menuReference.baselineOffset + menuInk.y + logoSize / 2
  readonly property real appSize: indicatorMetrics.tightBoundingRect("S1").height * 0.85 * 1.2
  readonly property var stations: {
    var numbers = Object.keys(stationApps || {}).map(Number)
    if (numbers.indexOf(stationNumber) === -1) numbers.push(stationNumber)
    return numbers.sort(function(a, b) { return a - b })
  }
  property int groupsRevision: 0
  readonly property var currentGroup: {
    var revision = groupsRevision
    return stationGroups.itemAt(stations.indexOf(stationNumber))
  }
  readonly property real currentOffset: currentGroup ? (vertical ? currentGroup.y : currentGroup.x) : 0
  property real revealProgress: expanded && showApps ? 1 : 0
  readonly property real collapsedExtent: vertical ? barSize : indicatorMetrics.tightBoundingRect("S" + stationNumber).width
  readonly property real fullExtent: vertical ? groups.implicitHeight : groups.implicitWidth
  readonly property real revealExtent: collapsedExtent + Math.max(0, fullExtent - collapsedExtent) * revealProgress
  readonly property real logoExtent: vertical ? barSize : logoSize
  readonly property real arrowExtent: vertical ? barSize : arrowMetrics.tightBoundingRect.width
  // The preceding stock Omarchy menu contributes its own 7.5-unit end inset.
  readonly property real leadingInset: Math.max(0, mainGap - Style.spaceReal(7.5)
    - (menuMetrics.advanceWidth("\ue900") - menuInk.width) / 2)
  readonly property real length: leadingInset + logoExtent + mainGap + revealExtent + (showApps ? mainGap + arrowExtent : 0)
  implicitWidth: vertical ? barSize : length
  implicitHeight: vertical ? length : barSize
  onShowAppsChanged: if (!showApps) expanded = false
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
    fixedWidth: root.vertical ? root.barSize : root.logoSize
    fixedHeight: root.barSize
    onPressed: root.pressed()
    Text { id: menuReference; anchors.centerIn: parent; visible: false; text: "\ue900"; font: menuMetrics.font }
    Station.StationMark {
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
    width: root.vertical ? root.barSize : root.revealExtent + (root.showApps ? root.mainGap + root.arrowExtent : 0)
    height: root.vertical ? root.revealExtent + (root.showApps ? root.mainGap + root.arrowExtent : 0) : root.barSize
    HoverHandler { onHoveredChanged: root.expanded = hovered && root.showApps }
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
            readonly property var apps: root.stationApps[modelData] || []
            columns: root.vertical ? 1 : 2
            spacing: root.labelGap
            Ui.WidgetButton {
              id: stationButton
              objectName: "stationLabel-" + group.modelData
              bar: root.bar
              text: "S" + group.modelData
              opacity: group.modelData === root.stationNumber ? 1 : root.revealProgress
              Behavior on opacity { enabled: false }
              tooltipText: "Station " + group.modelData
              labelVisible: false; hasVisualContent: true
              fixedWidth: root.vertical ? root.barSize : indicatorMetrics.tightBoundingRect(stationLabel.text).width
              fixedHeight: root.barSize
              onPressed: root.stationSelected(group.modelData)
              Text {
                id: stationLabel
                text: stationButton.text; font: indicatorMetrics.font; color: stationButton.foreground
                x: root.vertical ? (parent.width - implicitWidth) / 2 : -indicatorMetrics.tightBoundingRect(text).x
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
                  tooltipText: "Station " + group.modelData + ": " + modelData.title
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
      visible: root.showApps
      text: "\uf054"
      labelVisible: false; hasVisualContent: true
      objectName: "stationExpander"
      tooltipText: "Stations and open apps"
      x: root.vertical ? 0 : root.revealExtent + root.mainGap
      y: root.vertical ? root.revealExtent + root.mainGap : 0
      fixedWidth: root.arrowExtent
      fixedHeight: root.barSize
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
