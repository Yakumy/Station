// The closed surface a replacement bar's panel receives. Extend this file,
// BarServiceProxy.qml, WallpaperProxy.qml and the bridge tests together. Never add
// a QObject or callback: the snapshot crosses the bridge as detached JSON.
function snapshot(service) {
  var wallpaper = service.wallpaper
  return JSON.parse(JSON.stringify({
    windowSettingsBusy: service.windowSettingsBusy,
    currentStation: service.currentStation,
    openApps: service.openApps,
    workspaceApps: service.workspaceApps,
    workspaceMap: service.workspaceMap,
    workspaceTarget: service.workspaceTarget,
    displayDraft: service.displayDraft,
    bindStatuses: service.bindStatuses,
    config: service.config,
    monitorBarMinimums: service.monitorBarMinimums,
    monitorBarMaximumContents: service.monitorBarMaximumContents,
    draftMode: service.draftMode,
    draftSingleTarget: service.draftSingleTarget,
    draftEditable: service.draftEditable,
    state: service.state,
    layoutError: service.layoutError,
    previewBusy: service.previewBusy,
    previewSeconds: service.previewSeconds,
    panelEvacuationWaiting: service.panelEvacuationWaiting,
    panelEvacuationSerial: service.panelEvacuationSerial,
    panelEvacuationFrom: service.panelEvacuationFrom,
    panelEvacuationReleases: service.panelEvacuationReleases,
    panelScreenName: service.panelScreenName,
    panelTransferUntil: service.panelTransferUntil,
    panelWanted: service.panelWanted,
    rememberedTab: service.rememberedTab,
    rememberedDisplayName: service.rememberedDisplayName,
    displayWidgetEnabled: service.displayWidgetEnabled,
    workspaceWidgetEnabled: service.workspaceWidgetEnabled,
    pluginVersion: service.manifest && service.manifest.version ? String(service.manifest.version) : "",
    wallpaper: {
      draft: wallpaper.draft,
      layout: wallpaper.layout,
      busy: wallpaper.busy,
      importBusy: wallpaper.importBusy,
      notice: wallpaper.notice,
      noticeError: wallpaper.noticeError,
      pickerBusy: wallpaper.pickerBusy,
      themePath: wallpaper.themePath,
      dirty: wallpaper.dirty
    }
  }))
}

function actions(service) {
  return {
    switchStation: function(value) { return service.switchStation(value) },
    showWorkspace: function(value, output) { return service.showWorkspace(value, output) },
    setSetting: function(name, value) { return service.setSetting(name, value) },
    setModeValue: function(mode, target) { return service.setModeValue(mode, target) },
    setDirectionValue: function(value) { return service.setDirectionValue(value) },
    setBinding: function(id, combo) { return service.setBinding(id, combo) },
    approveBinding: function(combo) { return service.approveBinding(combo) },
    setDisplayValue: function(name, key, value) { return service.setDisplayValue(name, key, value) },
    setDisplayTransform: function(name, value) { return service.setDisplayTransform(name, value) },
    setDisplayPosition: function(name, x, y) { return service.setDisplayPosition(name, x, y) },
    setDisplayEnabled: function(name, enabled) { return service.setDisplayEnabled(name, enabled) },
    setMonitorBarEnabled: function(name, enabled) { return service.setMonitorBarEnabled(name, enabled) },
    setMonitorBarPosition: function(name, position) { return service.setMonitorBarPosition(name, position) },
    setMonitorBarWidth: function(name, width) { return service.setMonitorBarWidth(name, width) },
    setMonitorBarHeight: function(name, height) { return service.setMonitorBarHeight(name, height) },
    setMonitorBarBackground: function(name, background) { return service.setMonitorBarBackground(name, background) },
    setMonitorBarStyle: function(name, style) { return service.setMonitorBarStyle(name, style) },
    setMonitorBarContentSize: function(name, contentSize) { return service.setMonitorBarContentSize(name, contentSize) },
    reportMonitorBarMinimum: function(name, value) { return service.reportMonitorBarMinimum(name, value) },
    reportMonitorBarMaximumContent: function(name, value) { return service.reportMonitorBarMaximumContent(name, value) },
    monitorBar: function(name) { return service.monitorBar(name) },
    monitorBarMaximumHeight: function(name) { return service.monitorBarMaximumHeight(name) },
    monitorBarMinimum: function(name) { return service.monitorBarMinimum(name) },
    monitorBarMaximumContent: function(name) { return service.monitorBarMaximumContent(name) },
    applyDisplaySetting: function(name, key, value) { return service.applyDisplaySetting(name, key, value) },
    swapRole: function(name, roleIndex) { return service.swapRole(name, roleIndex) },
    displayEnabled: function(name) { return service.displayEnabled(name) },
    roleOf: function(name) { return service.roleOf(name) },
    previewLayout: function() { return service.previewLayout() },
    keepPreview: function() { return service.keepPreview() },
    revertPreview: function(reason) { return service.revertPreview(reason || "") },
    acquireStockLeases: function() { return service.acquireStockLeases() },
    acknowledgePanelEvacuation: function(serial, screenName) {
      return service.acknowledgePanelEvacuation(serial, screenName)
    },
    setPanelWanted: function(value) { return service.setPanelWanted(value) },
    setPanelScreenName: function(value) { return service.setPanelScreenName(value) },
    setPanelTransferUntil: function(value) { return service.setPanelTransferUntil(value) },
    setWindowSetting: function(key, value) { return service.setWindowSetting(key, value) },
    setRememberedTab: function(value) { return service.setRememberedTab(value) },
    setRememberedDisplayName: function(value) { return service.setRememberedDisplayName(value) },
    wallpaperChoose: function(identity) { return service.wallpaper.choose(identity) },
    wallpaperChange: function(key, value) { return service.wallpaper.change(key, value) },
    wallpaperFrame: function(value) { return service.wallpaper.frame(value) },
    wallpaperFrameDisplay: function(identity, value) { return service.wallpaper.frameDisplay(identity, value) },
    wallpaperReset: function() { return service.wallpaper.reset() },
    wallpaperUseTheme: function() { return service.wallpaper.useTheme() },
    wallpaperApply: function() { return service.wallpaper.apply() }
  }
}

if (typeof module !== "undefined") module.exports = { snapshot: snapshot, actions: actions }
