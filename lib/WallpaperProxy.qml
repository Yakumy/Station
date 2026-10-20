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
  readonly property bool dirty: snapshot ? snapshot.dirty === true : false

  function call(name, args) { return api ? api.call(name, args) : undefined }
  function change(key, value) { return call("wallpaperChange", [key, value]) }
  function frame(value) { return call("wallpaperFrame", [value]) }
  function reset() { return call("wallpaperReset", []) }
  function useTheme() { return call("wallpaperUseTheme", []) }
  function apply() { return call("wallpaperApply", []) }
}
