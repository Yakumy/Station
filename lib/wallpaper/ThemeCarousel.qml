import QtQuick
import qs.Ui as Ui
import qs.Commons

// A chooser floating over the layout canvas, which stays visible behind it. Left and
// Right browse, Return or a click on the centered card chooses, Escape closes.
// Items are { key, image, label }.
Item {
  id: root
  required property var tokens
  property var items: []
  // The key to start on, read when the items first arrive.
  property string current: ""
  property string emptyText: ""
  signal picked(string key)
  signal closed()
  readonly property int count: shown.length
  readonly property int index: list.currentIndex
  readonly property var currentItem: index >= 0 && index < shown.length ? shown[index] : null
  // The panel reads the controller through a polled bridge, which hands over a new
  // array on every unrelated change. Rebuilding the list would lose the position.
  property var shown: []
  property string shownText: ""
  // Until the viewer browses, the start follows current, which can settle after items.
  property bool moved: false
  // The centered card is 20% larger than its neighbours' full size.
  readonly property real activeScale: 1.2
  readonly property real restScale: 0.8
  clip: true
  focus: true

  property bool ready: false
  onItemsChanged: if (ready) sync()
  onCurrentChanged: if (ready && !moved) { shownText = ""; sync() }
  // Both inputs are bound by then, so the first position honors current.
  Component.onCompleted: { ready = true; sync() }
  function sync() {
    var text = JSON.stringify(items || [])
    if (text === shownText) return
    var key = currentItem && moved ? currentItem.key : current
    shownText = text
    shown = JSON.parse(text)
    // Assigned here, not bound, so the index below lands on the new model.
    list.model = shown
    if (!shown.length) return
    var found = shown.findIndex(function(item) { return item.key === key })
    if (found < 0 && !moved) found = shown.findIndex(function(item) { return item.key === root.current })
    list.currentIndex = Math.max(0, found)
    Qt.callLater(function() { list.positionViewAtIndex(list.currentIndex, ListView.Center) })
  }
  function step(delta) {
    moved = true
    if (shown.length) list.currentIndex = (list.currentIndex + delta + shown.length) % shown.length
  }
  function choose() { if (currentItem) picked(currentItem.key) }

  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Left || event.text === "h") step(-1)
    else if (event.key === Qt.Key_Right || event.text === "l") step(1)
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) choose()
    else if (event.key === Qt.Key_Escape) closed()
    // Keep Up and Down from scrolling the panel underneath.
    else if (event.key !== Qt.Key_Up && event.key !== Qt.Key_Down) return
    event.accepted = true
  }

  ListView {
    id: list
    objectName: "themeCarouselList"
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: caption.top
    anchors.topMargin: root.tokens.space2
    anchors.bottomMargin: root.tokens.space2
    orientation: ListView.Horizontal
    // Sized so the enlarged centered card still fits the view's height.
    readonly property real cardWidth: Math.max(1, Math.min(width * 0.48, height * 16 / 9 / root.activeScale))
    spacing: root.tokens.space3
    // ApplyRange, not StrictlyEnforceRange: a strict range moves the current index to
    // whichever card sits centered while the view first takes its size. The header and
    // footer let the first and last cards reach the center.
    highlightRangeMode: ListView.ApplyRange
    header: Item { width: list.preferredHighlightBegin - list.spacing; height: 1 }
    footer: Item { width: list.preferredHighlightBegin - list.spacing; height: 1 }
    preferredHighlightBegin: (width - cardWidth) / 2
    preferredHighlightEnd: preferredHighlightBegin + cardWidth
    highlightMoveDuration: 160
    // The range applies to the highlight item, so the view needs one, even an empty one.
    highlight: Item {}
    // Browsing is by key, click and wheel; a flick would fight the snapping.
    interactive: false
    cacheBuffer: Math.ceil(cardWidth * 2)
    delegate: Item {
      id: slot
      required property var modelData
      required property int index
      readonly property bool active: ListView.isCurrentItem
      // The enlarged card overlaps its neighbours' edges, so it draws above them.
      z: active ? 1 : 0
      width: list.cardWidth
      height: list.height
      Item {
        id: card
        objectName: "themeCarouselCard"
        anchors.centerIn: parent
        width: parent.width
        height: width * 9 / 16
        scale: slot.active ? root.activeScale : root.restScale
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Image {
          anchors.fill: parent
          source: Util.fileUrl(slot.modelData.image)
          sourceSize.width: Math.ceil(card.width * 2)
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          mipmap: true
          clip: true
        }
        Ui.BorderSurface {
          anchors.fill: parent
          color: "transparent"
          borderSpec: slot.active ? Border.flat(Color.accent, Style.normalBorderWidth * 2)
            : Border.controlSpec("normal", Color.popups.text, Color.accent)
          radius: Style.cornerRadius
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            root.forceActiveFocus()
            if (slot.active) root.choose()
            else { root.moved = true; list.currentIndex = slot.index }
          }
        }
      }
    }
  }
  // Behind the cards: holds pointer input so it never reaches the layout underneath.
  MouseArea {
    z: -1
    anchors.fill: parent
    acceptedButtons: Qt.AllButtons
    onPressed: root.forceActiveFocus()
    onWheel: function(wheel) {
      var delta = Math.abs(wheel.angleDelta.x) > Math.abs(wheel.angleDelta.y) ? wheel.angleDelta.x : wheel.angleDelta.y
      if (delta) root.step(delta > 0 ? -1 : 1)
      wheel.accepted = true
    }
  }
  Column {
    id: caption
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: root.tokens.space2
    width: parent.width - root.tokens.space4 * 2
    spacing: root.tokens.space1
    // A plate under the name keeps it legible over the canvas grid.
    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      width: Math.min(parent.width, label.implicitWidth + root.tokens.space3 * 2)
      height: label.implicitHeight + root.tokens.space1 * 2
      color: Color.popups.background
      radius: Style.cornerRadius
      Text {
        id: label
        objectName: "themeCarouselLabel"
        anchors.centerIn: parent
        width: Math.min(implicitWidth, parent.parent.width - root.tokens.space3 * 2)
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        elide: Text.ElideMiddle
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.title
        font.weight: Font.DemiBold
        text: root.currentItem ? root.currentItem.label + "  " + (root.index + 1) + " / " + root.count : root.emptyText
      }
    }
  }
}
