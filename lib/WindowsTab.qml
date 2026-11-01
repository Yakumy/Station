import QtQuick
import qs.Ui as Ui
import qs.Commons
import qs.Commons as Commons
import "Windows.js" as Windows

Column {
  id: root
  required property var panelRoot
  property var values: Windows.clean(panelRoot.service ? panelRoot.service.config.windows : null)
  readonly property var savedValues: panelRoot.service ? panelRoot.service.config.windows : null
  onSavedValuesChanged: values = Windows.clean(savedValues)
  property bool swapped: false
  property bool animateSwap: false
  Timer { id: swapEnd; interval: 500; onTriggered: root.animateSwap = false }
  readonly property var barSettings: panelRoot.selectedDisplay && panelRoot.service ? panelRoot.service.monitorBar(panelRoot.selectedDisplay.name) : ({})
  readonly property real thickness: Number(barSettings.height) || (barSettings.position === "left" || barSettings.position === "right" ? Style.bar.sizeVertical : Style.bar.sizeHorizontal)
  function preview(key, value) { var next = Object.assign({}, values); next[key] = value; values = next }
  component Caption: Text {
    color: root.panelRoot.textPrimary
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }
  Row {
    width: parent.width
    height: Style.space(428)
    Column {
      width: parent.width * 0.576
      Item {
        width: parent.width; height: Style.space(28)
        Ui.PanelSectionHeader { anchors.left: parent.left; anchors.leftMargin: root.panelRoot.regionPadH; text: "LAYOUT"; foreground: root.panelRoot.textPrimary }
      }
      Ui.BorderSurface {
        width: parent.width - root.panelRoot.regionPadH * 2
        height: Style.space(370)
        anchors.horizontalCenter: parent.horizontalCenter
        clip: true
        color: Commons.Color.popups.background
        borderSpec: Border.controlSpec("normal", Commons.Color.popups.text, Commons.Color.accent)
        radius: Style.cornerRadius
        Canvas {
          anchors.fill: parent
          opacity: 0.22
          property color dotColor: Commons.Color.popups.text
          onDotColorChanged: requestPaint()
          onWidthChanged: requestPaint()
          onHeightChanged: requestPaint()
          onPaint: {
            var context = getContext("2d")
            context.clearRect(0, 0, width, height)
            context.fillStyle = dotColor
            var gap = Style.space(16), radius = Math.max(Style.space(0.7), 0.5)
            for (var x = gap; x < width; x += gap) for (var y = gap; y < height; y += gap) {
              context.beginPath(); context.arc(x, y, radius, 0, Math.PI * 2); context.fill()
            }
          }
        }

        Rectangle {
          id: screen
          anchors.centerIn: parent
          width: parent.width * 0.8
          height: width * 0.625
          color: Commons.Color.menu.selectedBackground
          border.color: Commons.Color.accent
          border.width: Style.normalBorderWidth
          radius: Style.cornerRadius
          readonly property real factor: width / 1000
          readonly property real gap: root.values.innerGap * factor
          readonly property var gaps: Windows.gaps(root.values, root.barSettings)
          readonly property real barSize: root.barSettings.enabled !== false ? root.thickness * factor : 0
          Rectangle {
            color: Commons.Color.accent
            radius: Style.cornerRadius
            visible: root.barSettings.enabled !== false
            x: root.barSettings.position === "right" ? parent.width - width : 0
            y: root.barSettings.position === "bottom" ? parent.height - height : 0
            width: root.barSettings.position === "left" || root.barSettings.position === "right" ? screen.barSize : parent.width
            height: root.barSettings.position === "left" || root.barSettings.position === "right" ? parent.height : screen.barSize
          }
          Item {
            id: area
            anchors.fill: parent
            anchors.topMargin: screen.gaps.top * screen.factor + screen.border.width + (root.barSettings.position === "top" ? screen.barSize : 0)
            anchors.rightMargin: screen.gaps.right * screen.factor + screen.border.width + (root.barSettings.position === "right" ? screen.barSize : 0)
            anchors.bottomMargin: screen.gaps.bottom * screen.factor + screen.border.width + (root.barSettings.position === "bottom" ? screen.barSize : 0)
            anchors.leftMargin: screen.gaps.left * screen.factor + screen.border.width + (root.barSettings.position === "left" ? screen.barSize : 0)
            Repeater {
              model: 2
              Rectangle {
                required property int index
                readonly property bool onRight: (index === 1) !== root.swapped
                width: (area.width - screen.gap) * (index === 0 ? root.values.split / 100 : 1 - root.values.split / 100)
                height: area.height
                x: onRight ? area.width - width : 0
                color: Commons.Color.popups.background
                border.color: index === 0 ? Commons.Color.accent : Commons.Color.popups.text
                border.width: Style.normalBorderWidth
                radius: root.values.rounding * screen.factor
                Behavior on x { enabled: root.animateSwap; NumberAnimation { duration: root.values.speed === 0 ? 0 : 400 / root.values.speed; easing.type: Easing.OutCubic } }
                Caption { anchors.centerIn: parent; text: index === 0 ? "NEXT WINDOW" : "WINDOW" }
              }
            }
          }
        }
      }
    }
    Rectangle { width: Math.max(1, Style.normalBorderWidth); height: parent.height; color: Commons.Color.popups.text; opacity: 0.12 }
    Column {
      width: parent.width * 0.424 - Math.max(1, Style.normalBorderWidth)
      Item { width: parent.width; height: Style.space(28); Caption { anchors.left: parent.left; anchors.leftMargin: Style.space(28); anchors.verticalCenter: parent.verticalCenter; width: parent.width - Style.space(56); elide: Text.ElideRight; text: root.panelRoot.selectedDisplay ? "Selected: " + root.panelRoot.selectedDisplay.name : "All monitors" } }
      Ui.BorderSurface {
        width: parent.width - Style.space(56); height: Style.space(370)
        anchors.horizontalCenter: parent.horizontalCenter
        color: Commons.Color.popups.background
        borderSpec: Border.controlSpec("normal", Commons.Color.popups.text, Commons.Color.accent)
        radius: Style.cornerRadius
        Column {
          anchors.fill: parent
          Repeater {
            model: [{key:"innerGap",label:"INNER GAP"},{key:"outerGap",label:"OUTER GAP"},{key:"split",label:"NEXT WINDOW SIZE"},{key:"rounding",label:"BORDER ROUNDNESS"},{key:"speed",label:"ANIMATION SPEED"}]
            Item {
              id: row
              required property var modelData
              required property int index
              width: parent.width; height: Style.space(74)
              Caption { anchors.left: parent.left; anchors.leftMargin: root.panelRoot.space3; anchors.top: parent.top; anchors.topMargin: root.panelRoot.space2; text: row.modelData.label }
              Caption { anchors.right: parent.right; anchors.rightMargin: root.panelRoot.space3; anchors.top: parent.top; anchors.topMargin: root.panelRoot.space2; text: root.values[row.modelData.key] + (row.index === 2 ? "%" : row.index === 4 ? "×" : " px") }
              Ui.PanelSlider {
                id: slider
                width: parent.width - root.panelRoot.space3 * 2
                anchors.centerIn: parent
                bar: root.panelRoot.bar
                minimum: Windows.limits[row.modelData.key][0]
                maximum: Windows.limits[row.modelData.key][1]
                enabled: root.panelRoot.service && !root.panelRoot.service.windowSettingsBusy
                integer: true
                value: root.values[row.modelData.key]
                onMoved: function(value) { root.preview(row.modelData.key, value) }
                onReleased: function(value) {
                  if (row.modelData.key === "speed" && value !== Windows.clean(root.savedValues).speed) { root.animateSwap = true; root.swapped = !root.swapped; swapEnd.restart() }
                  root.panelRoot.service.setWindowSetting(row.modelData.key, value)
                }
                Rectangle {
                  visible: row.index < 2
                  x: Math.min(1, root.thickness / slider.maximum) * parent.width - width / 2
                  anchors.verticalCenter: parent.verticalCenter
                  width: Math.max(1, Style.normalBorderWidth); height: slider.trackHeight + Style.space(6)
                  color: Commons.Color.accent
                  MouseArea { anchors.fill: parent; anchors.margins: -Style.space(5); hoverEnabled: true; onEntered: { if (root.panelRoot.bar) root.panelRoot.bar.showTooltip(parent, "Bar thickness: " + root.thickness + " px") } onExited: { if (root.panelRoot.bar) root.panelRoot.bar.hideTooltip(parent) } }
                }
              }
              Ui.PanelSeparator { visible: row.index < 4; anchors.bottom: parent.bottom; width: parent.width; foreground: Commons.Color.popups.text }
            }
          }
        }
      }
    }
  }
  Ui.PanelSeparator { width: parent.width; foreground: Commons.Color.popups.text }
  Item { width: parent.width; height: Style.space(64); Caption { anchors.centerIn: parent; text: "Change animation speed to preview · 0 disables animations" } }
}
