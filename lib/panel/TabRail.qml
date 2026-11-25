import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Tabs.js" as Tabs

// The panel's tab row. It scrolls sideways when the tabs do not fit.
Flickable {
  id: tabRail
  required property var tokens
  property int selectedTab: 0
  property int conflictCount: 0
  signal tabSelected(int index)
  height: tabRail.tokens.controlHeight + tabRail.tokens.space1
  contentWidth: tabs.width + tabRail.tokens.regionPadH * 2
  contentHeight: height
  clip: true
  interactive: contentWidth > width
  boundsBehavior: Flickable.StopAtBounds
  WheelHandler {
    target: null
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: function(event) {
      var delta = event.pixelDelta.y || event.pixelDelta.x
        || event.angleDelta.y / 120 * tabRail.tokens.controlHeight * 2
        || event.angleDelta.x / 120 * tabRail.tokens.controlHeight * 2
      var limit = Math.max(0, tabRail.contentWidth - tabRail.width)
      tabRail.contentX = Math.max(0, Math.min(limit, tabRail.contentX - delta))
      event.accepted = true
    }
  }
  Row {
    id: tabs
    anchors.left: parent.left
    anchors.leftMargin: tabRail.tokens.regionPadH
    anchors.bottom: parent.bottom
    height: parent.height
    Repeater {
      model: Tabs.labels()
      delegate: Item {
        id: tab
        required property int index
        required property string modelData
        readonly property bool conflicted: index === Tabs.index("keybindings") && tabRail.conflictCount > 0
        height: tabs.height
        // 28px between tabs; the row's left margin carries the 24px
        // region inset so the first tab still aligns with the logo.
        width: tabLabel.implicitWidth + tabRail.tokens.space4 + tabRail.tokens.space3
          + (conflicted ? badge.width + tabRail.tokens.space1 : 0)
        Text {
          id: tabLabel
          anchors.centerIn: parent
          anchors.horizontalCenterOffset: tab.conflicted
            ? -(badge.width + tabRail.tokens.space1) / 2 : 0
          text: tab.modelData
          // Selection is carried by the accent rule underneath, so the
          // label only steps between the dim and full text tokens.
          color: tab.conflicted ? Commons.Color.urgent
            : (tabRail.selectedTab === tab.index ? tabRail.tokens.textPrimary : tabRail.tokens.textDim)
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
        Rectangle {
          id: badge
          visible: tab.conflicted
          anchors.left: tabLabel.right
          anchors.leftMargin: tabRail.tokens.space1
          anchors.verticalCenter: tabLabel.verticalCenter
          width: Math.max(tabRail.tokens.space4, badgeText.implicitWidth + tabRail.tokens.space2)
          height: tabRail.tokens.space4
          color: Commons.Color.urgent
          radius: Style.cornerRadius
          Text {
            id: badgeText
            anchors.centerIn: parent
            text: tabRail.conflictCount
            color: Commons.Color.popups.background
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.weight: Font.DemiBold
          }
        }
        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: tabRail.tokens.tabUnderline
          color: tab.conflicted ? Commons.Color.urgent : Commons.Color.accent
          visible: tabRail.selectedTab === tab.index
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: tabRail.tabSelected(tab.index)
        }
      }
    }
  }
}
