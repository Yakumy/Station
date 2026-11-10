import QtQuick
import qs.Ui as Ui
import qs.Commons
import qs.Commons as Commons
import "Grid.js" as Grid
import "." as Stations

// Workspace mode, count, bar indicator style and open apps. The layout shows what
// each output gets before the migration commits it.
Column {
  id: root
  required property var tokens
  required property var service
  readonly property real pad: tokens.regionPadH
  readonly property var config: service ? service.config : ({})
  readonly property string mode: Grid.MODES.indexOf(config.workspaceMode) !== -1 ? config.workspaceMode : "station"
  readonly property var outputs: service && service.workspaceTarget ? service.workspaceTarget.outputs || [] : []
  readonly property int outputCount: Math.max(1, outputs.length)
  readonly property var limits: Grid.limits(mode, outputCount)
  readonly property int count: Grid.total(mode, outputCount,
    mode === "station" ? config.minStations : (config.workspaceCounts ? config.workspaceCounts[mode] : null))
  readonly property var assigned: Grid.assigned(mode, outputCount, count)
  readonly property bool editable: !!service && service.state === "idle"
  // The modes differ only across monitors, so one monitor locks the selector.
  readonly property bool singleOutput: outputs.length <= 1
  readonly property real modeNoteHeight: singleOutput ? Style.space(22) : 0
  spacing: 0

  function changeCount(delta) {
    var next = Math.max(limits.min, Math.min(limits.max, count + delta))
    if (service && next !== count) service.setSetting("workspaceCount", next)
  }

  component Caption: Text {
    color: root.tokens.textDim
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }
  component RowLabel: Text {
    color: root.tokens.textPrimary
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    elide: Text.ElideRight
  }
  component ModeSelector: Ui.BorderSurface {
    id: selector
    property string value: ""
    property var options: []
    signal changed(string value)
    opacity: enabled ? 1 : root.tokens.disabledOpacity
    color: Commons.Color.popups.background
    borderSpec: Border.controlSpec("normal", Commons.Color.popups.text, Commons.Color.accent)
    radius: Style.cornerRadius
    clip: true

    Row {
      anchors.fill: parent
      anchors.margins: Math.max(1, Style.normalBorderWidth)
      spacing: 0
      Repeater {
        model: selector.options
        delegate: Item {
          required property var modelData
          required property int index
          width: (selector.width - Math.max(1, Style.normalBorderWidth) * 2) / selector.options.length
          height: parent.height
          Ui.Button {
            anchors.fill: parent
            objectName: "workspaceMode-" + modelData.value
            text: modelData.label
            selected: selector.enabled && selector.value === modelData.value
            focusable: true
            foreground: Commons.Color.popups.text
            background: Commons.Color.popups.background
            accent: Commons.Color.accent
            onClicked: selector.changed(modelData.value)
          }
          Rectangle {
            visible: index > 0
            anchors.left: parent.left
            height: parent.height
            width: Math.max(1, Style.normalBorderWidth)
            color: Border.color(Border.controlSpec("normal", Commons.Color.popups.text, Commons.Color.accent))
          }
        }
      }
    }
  }

  Row {
    width: parent.width
    height: Style.space(428)
    Column {
      id: left
      width: parent.width * 0.576
      Item {
        width: parent.width; height: Style.space(28)
        Ui.PanelSectionHeader {
          anchors.left: parent.left; anchors.leftMargin: root.pad
          anchors.verticalCenter: parent.verticalCenter
          text: "LAYOUT"; foreground: Commons.Color.popups.text
        }
        Caption {
          anchors.right: parent.right; anchors.rightMargin: root.pad
          anchors.verticalCenter: parent.verticalCenter
          text: "SCROLL TO ZOOM"
        }
      }
      Stations.WorkspacesLayout {
        x: root.pad; width: parent.width - root.pad * 2; height: Style.space(370)
        service: root.service
        tokens: root.tokens
        outputs: root.outputs
        assigned: root.assigned
      }
      Caption {
        x: root.pad; width: parent.width - root.pad * 2
        topPadding: root.tokens.space2
        wrapMode: Text.WordWrap
        text: "Monitor positions and roles follow Displays."
      }
    }
    Rectangle {
      width: Math.max(1, Style.normalBorderWidth); height: parent.height
      color: Commons.Color.popups.text; opacity: 0.12
    }
    Column {
      width: parent.width - left.width - Math.max(1, Style.normalBorderWidth)
      spacing: 0
      Item {
        width: parent.width; height: Style.space(28)
        Ui.PanelSectionHeader {
          anchors.left: parent.left; anchors.leftMargin: Style.space(28)
          anchors.verticalCenter: parent.verticalCenter
          text: "WORKSPACES"; foreground: Commons.Color.popups.text
        }
      }
      Ui.BorderSurface {
        id: controlFrame
        width: parent.width - Style.space(28) * 2
        height: Style.space(370)
        anchors.horizontalCenter: parent.horizontalCenter
        color: Commons.Color.popups.background
        borderSpec: Border.controlSpec("normal", Commons.Color.popups.text, Commons.Color.accent)
        radius: Style.cornerRadius
        Column {
          anchors.fill: parent
          spacing: 0
          Item {
            width: parent.width; height: controlFrame.height / 5 + root.modeNoteHeight
            Caption {
              anchors.left: parent.left; anchors.leftMargin: root.tokens.space3
              anchors.top: parent.top; anchors.topMargin: root.tokens.space2
              text: "MODE"
            }
            ModeSelector {
              objectName: "workspaceModeSelector"
              enabled: root.editable && !root.singleOutput
              anchors.left: parent.left; anchors.leftMargin: root.tokens.space3
              anchors.right: parent.right; anchors.rightMargin: root.tokens.space3
              anchors.bottom: parent.bottom; anchors.bottomMargin: root.tokens.space2 + root.modeNoteHeight
              height: Style.spacing.controlHeight
              value: root.mode
              options: [{ value: "station", label: "Station" }, { value: "repetitive", label: "Repetitive" },
                { value: "nonrepetitive", label: "Non-repetitive" }]
              onChanged: function(value) { if (root.service) root.service.setSetting("workspaceMode", value) }
            }
            Caption {
              objectName: "workspaceModeNote"
              visible: root.singleOutput
              anchors.left: parent.left; anchors.leftMargin: root.tokens.space3
              anchors.right: parent.right; anchors.rightMargin: root.tokens.space3
              anchors.bottom: parent.bottom; anchors.bottomMargin: root.tokens.space2
              elide: Text.ElideRight
              text: "Works only on multiple monitors"
            }
            Ui.PanelSeparator { anchors.bottom: parent.bottom; width: parent.width; foreground: Commons.Color.popups.text }
          }
          Item {
            width: parent.width; height: controlFrame.height / 5
            enabled: root.editable
            Column {
              anchors.left: parent.left; anchors.leftMargin: root.tokens.space3
              anchors.right: stepper.left; anchors.rightMargin: root.tokens.space2
              anchors.verticalCenter: parent.verticalCenter
              RowLabel {
                width: parent.width
                text: root.mode === "station" ? "Stations" : "Workspaces"
              }
              Caption {
                width: parent.width
                elide: Text.ElideRight
                text: root.mode === "station" ? "Each station has one workspace per monitor"
                  : root.mode === "repetitive" ? "Every monitor numbers its own from 1"
                  : "Each number belongs to one monitor"
              }
            }
            Row {
              id: stepper
              anchors.right: parent.right; anchors.rightMargin: root.tokens.space3
              anchors.verticalCenter: parent.verticalCenter
              spacing: root.tokens.space2
              Ui.Button {
                objectName: "workspaceCountDecrease"
                text: "-"; bordered: true
                width: Style.spacing.controlHeight; height: Style.spacing.controlHeight
                enabled: root.editable && root.count > root.limits.min
                opacity: enabled ? 1 : root.tokens.disabledOpacity
                onClicked: root.changeCount(-1)
              }
              Text {
                objectName: "workspaceCountValue"
                width: Style.space(32)
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignHCenter
                text: String(root.count)
                color: root.tokens.textPrimary
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }
              Ui.Button {
                objectName: "workspaceCountIncrease"
                text: "+"; bordered: true
                width: Style.spacing.controlHeight; height: Style.spacing.controlHeight
                enabled: root.editable && root.count < root.limits.max
                opacity: enabled ? 1 : root.tokens.disabledOpacity
                onClicked: root.changeCount(1)
              }
            }
            Ui.PanelSeparator { anchors.bottom: parent.bottom; width: parent.width; foreground: Commons.Color.popups.text }
          }
          Item {
            width: parent.width; height: controlFrame.height / 5
            RowLabel {
              anchors.left: parent.left; anchors.leftMargin: root.tokens.space3
              anchors.right: styleValue.left; anchors.rightMargin: root.tokens.space2
              anchors.verticalCenter: parent.verticalCenter
              text: "Indicator style"
            }
            Ui.Dropdown {
              id: styleValue
              objectName: "indicatorStyleDropdown"
              anchors.right: parent.right; anchors.rightMargin: root.tokens.space3
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(130)
              showLabel: false
              value: root.config.indicatorStyle || "prefixed"
              options: [
                { value: "prefixed", label: root.mode === "station" ? "S1 S2 S3" : "W1 W2 W3" },
                { value: "number", label: "1 2 3" },
                { value: "roman", label: "I II III" },
                { value: "dots", label: "● ○ ○" }
              ]
              foreground: root.tokens.textPrimary
              onChanged: function(value) { if (root.service) root.service.setSetting("indicatorStyle", value) }
            }
            Ui.PanelSeparator { anchors.bottom: parent.bottom; width: parent.width; foreground: Commons.Color.popups.text }
          }
          Item {
            width: parent.width; height: controlFrame.height / 5
            RowLabel {
              anchors.left: parent.left; anchors.leftMargin: root.tokens.space3
              anchors.right: appsValue.left; anchors.rightMargin: root.tokens.space2
              anchors.verticalCenter: parent.verticalCenter
              text: "Open apps on indicator"
            }
            Ui.Dropdown {
              id: appsValue
              objectName: "stationAppsModeDropdown"
              anchors.right: parent.right; anchors.rightMargin: root.tokens.space3
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(130)
              showLabel: false
              value: root.config.stationAppsMode || "hover"
              options: [
                { value: "hover", label: "On hover" },
                { value: "hide", label: "Off" },
                { value: "always", label: "Always on" }
              ]
              foreground: root.tokens.textPrimary
              onChanged: function(value) { if (root.service) root.service.setSetting("stationAppsMode", value) }
            }
            Ui.PanelSeparator { anchors.bottom: parent.bottom; width: parent.width; foreground: Commons.Color.popups.text }
          }
          Item {
            width: parent.width; height: controlFrame.height / 5 - root.modeNoteHeight
          }
        }
      }
    }
  }
  Ui.PanelSeparator { width: parent.width; foreground: Commons.Color.popups.text }
}
