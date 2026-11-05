import QtQuick
import qs.Ui as Ui
import qs.Commons

// M0 only: the installed Display plugin's Panel -> BarIconButton +
// KeyboardPanel -> PanelKeyCatcher structure, without monitor effects.
Ui.Panel {
  id: root
  moduleName: "yakumy.station-m0"
  manageIpc: false
  property var service: bar && bar.shell ? bar.shell.serviceFor("yakumy.station-m0") : null
  function report() {
    if (service && (opened || !service.panelState.screen || (panel.screen && service.panelState.screen === panel.screen.name))) service.panelState = { opened: opened, width: panel.contentWidth,
      height: panel.contentHeight, focused: keyCatcher.activeFocus,
      x: panel.cardOrigin.x, y: panel.cardOrigin.y,
      screen: panel.screen ? panel.screen.name : "" }
  }
  Timer { interval: 100; repeat: true; running: true; onTriggered: root.report() }

  Ui.BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "S"
    onPressed: root.toggle()
  }

  Ui.KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(680))
    contentHeight: panel.fittedContentHeight(Style.space(560), Style.space(560))

    Ui.PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      Column {
        anchors.fill: parent
        spacing: Style.spacing.md
        Text {
          text: "Station · M0 platform probe"
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.title
        }
        Ui.PanelSeparator { width: parent.width; foreground: Color.foreground }
        Text {
          width: parent.width
          text: "Check widget anchoring, keyboard focus, Esc and outside-click dismissal."
          wrapMode: Text.WordWrap
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
        Text {
          text: "Panel content: " + Math.round(panel.contentWidth) + " × " + Math.round(panel.contentHeight)
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
