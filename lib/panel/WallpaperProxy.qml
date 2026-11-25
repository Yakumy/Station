import QtQuick

QtObject {
  id: root
  property var snapshot: null
  property var api: null

  readonly property var draft: snapshot && snapshot.draft ? snapshot.draft : ({})
  readonly property var layout: snapshot && snapshot.layout
    ? snapshot.layout : ({ displays: [], width: 0, height: 0, density: 1 })
  readonly property bool busy: snapshot ? snapshot.busy === true : false
  readonly property bool importBusy: snapshot ? snapshot.importBusy === true : false
  readonly property string notice: snapshot ? snapshot.notice : ""
  readonly property bool noticeError: snapshot ? snapshot.noticeError === true : false
  readonly property bool pickerBusy: snapshot ? snapshot.pickerBusy === true : false
  readonly property string themePath: snapshot ? snapshot.themePath : ""
  readonly property string themeName: snapshot && snapshot.themeName ? snapshot.themeName : ""
  readonly property var themes: snapshot && Array.isArray(snapshot.themes) ? snapshot.themes : []
  readonly property bool themesLoading: snapshot ? snapshot.themesLoading === true : false
  readonly property string pendingTheme: snapshot && snapshot.pendingTheme ? snapshot.pendingTheme : ""
  readonly property string pendingBackground: snapshot && snapshot.pendingBackground ? snapshot.pendingBackground : ""
  readonly property bool dirty: snapshot ? snapshot.dirty === true : false

  function call(name, args) { return api ? api.call(name, args) : undefined }
  function loadThemes() { return call("wallpaperLoadThemes", []) }
  function previewTheme(name) { return call("wallpaperPreviewTheme", [name]) }
  function previewBackground(path, identity) { return call("wallpaperPreviewBackground", [path, identity]) }
  function choose(identity) { return call("wallpaperChoose", [identity]) }
  function change(key, value) { return call("wallpaperChange", [key, value]) }
  function frame(value) { return call("wallpaperFrame", [value]) }
  function frameDisplay(identity, value) { return call("wallpaperFrameDisplay", [identity, value]) }
  function reset() { return call("wallpaperReset", []) }
  function apply() { return call("wallpaperApply", []) }
}
