import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "leomoon-studios.omarchy-world-clock"
  ipcTarget: "leomoon-studios.omarchy-world-clock"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  property string mode: "clocks"
  property var draftLocations: []
  property string settingsError: ""
  property string converterSource: "America/Vancouver"
  property string newLocationTimezone: "UTC"
  property bool resetArmed: false
  property bool cursorActive: false
  property int tabIndex: 0
  property string focusSection: "tabs"
  property int cursorRow: 0
  property int cursorColumn: 0
  property bool editorActive: false
  property bool pendingOpen: false

  // Plugin settings belong to the plugin. Bar layout changes may rewrite
  // shell.json, so never use its inline widget entry as a settings backend.
  property var durableSettings: ({
    locations: [{ label: "UTC", timezone: "UTC" }],
    hourFormat: "24",
    showAbbreviation: true,
    showUtcOffset: false,
    showTodayDate: false
  })
  property bool durableSettingsLoaded: false
  property bool settingsDirectoryReady: false
  readonly property string durableSettingsDirectory: Quickshell.env("HOME") + "/.config/" + moduleName
  readonly property string durableSettingsPath: durableSettingsDirectory + "/settings.json"

  Process {
    id: settingsDirectoryCreator
    command: ["/usr/bin/mkdir", "-p", root.durableSettingsDirectory]
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        console.warn(root.moduleName + ": unable to create settings directory")
        return
      }
      root.settingsDirectoryReady = true
      durableSettingsFile.reload()
    }
  }

  FileView {
    id: durableSettingsFile
    path: root.durableSettingsPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadDurableSettings(text())
    onFileChanged: reload()
    onLoadFailed: if (root.settingsDirectoryReady) root.bootstrapDurableSettings()
  }

  Component.onCompleted: settingsDirectoryCreator.running = true

  function settingsObject(value) {
    return value && typeof value === "object" && !Array.isArray(value) ? value : ({})
  }

  function loadDurableSettings(raw) {
    var parsed = null
    try {
      parsed = JSON.parse(String(raw || ""))
    } catch (e) {
      parsed = null
    }
    if (parsed && parsed.version === 1 && parsed.settings)
      durableSettings = settingsObject(parsed.settings)
    else
      bootstrapDurableSettings()
    durableSettingsLoaded = true
    finishPendingOpen()
  }

  function bootstrapDurableSettings() {
    durableSettingsLoaded = true
    durableSettingsFile.setText(JSON.stringify({ version: 1, settings: durableSettings }, null, 2) + "\n")
    finishPendingOpen()
  }

  function saveDurableSettings(value) {
    durableSettingsFile.setText(JSON.stringify({ version: 1, settings: value }, null, 2) + "\n")
  }

  function setting(name, fallback) {
    var value = durableSettings[name]
    return value === undefined || value === null ? fallback : value
  }

  function finishPendingOpen() {
    if (!pendingOpen || !durableSettingsLoaded) return
    pendingOpen = false
    open()
  }

  function modeIndex() {
    if (mode === "convert") return 1
    if (mode === "settings") return 2
    return 0
  }

  function bodyRowCount() {
    if (mode === "convert") return 3
    if (mode === "settings") return draftLocations.length + 6
    return 0
  }

  function bodyColumnCount(row) {
    if (mode === "convert") return row === 1 || row === 2 ? 2 : 1
    if (mode === "settings") {
      if (row < draftLocations.length) return 4
      if (row === draftLocations.length) return 3
      if (row === draftLocations.length + 5) return 3
    }
    return 1
  }

  function moveCursor(dx, dy) {
    if (!cursorActive) {
      cursorActive = true
      focusSection = "tabs"
      tabIndex = modeIndex()
      return
    }
    if (focusSection === "tabs") {
      if (dx !== 0) tabIndex = Math.max(0, Math.min(2, tabIndex + dx))
      else if (dy > 0 && bodyRowCount() > 0) {
        focusSection = "body"
        cursorRow = 0
        cursorColumn = 0
      }
      return
    }
    if (dy < 0 && cursorRow === 0) {
      focusSection = "tabs"
      tabIndex = modeIndex()
      return
    }
    if (dy !== 0) {
      cursorRow = Math.max(0, Math.min(bodyRowCount() - 1, cursorRow + dy))
      cursorColumn = Math.min(cursorColumn, bodyColumnCount(cursorRow) - 1)
    }
    if (dx !== 0)
      cursorColumn = Math.max(0, Math.min(bodyColumnCount(cursorRow) - 1, cursorColumn + dx))
  }

  function setBodyCursor(row, column) {
    cursorActive = true
    focusSection = "body"
    cursorRow = row
    cursorColumn = column
  }

  function finishEditing() {
    editorActive = false
    keyCatcher.forceActiveFocus()
  }

  function activateTab() {
    if (!cursorActive) return
    if (tabIndex === 0) mode = "clocks"
    else if (tabIndex === 1) enterConverter()
    else enterSettings()
  }

  function activateBody() {
    if (mode === "convert") {
      if (cursorRow === 0) converterTimezone.open()
      else if (cursorRow === 1) {
        if (cursorColumn === 0) conversionDate.forceActiveFocus()
        else conversionTime.forceActiveFocus()
      } else if (cursorColumn === 0) fillNow()
      else runConversion()
      return
    }
    if (mode !== "settings") return
    if (cursorRow < draftLocations.length) {
      var row = locationRepeater.itemAt(cursorRow)
      if (row) row.activateColumn(cursorColumn)
      return
    }
    var addRowIndex = draftLocations.length
    if (cursorRow === addRowIndex) {
      if (cursorColumn === 0) addTimezone.open()
      else if (cursorColumn === 1) addLabel.forceActiveFocus()
      else addDraftLocation()
    } else if (cursorRow === addRowIndex + 1) formatButton.clicked()
    else if (cursorRow === addRowIndex + 2) abbreviationButton.clicked()
    else if (cursorRow === addRowIndex + 3) offsetButton.clicked()
    else if (cursorRow === addRowIndex + 4) todayDateButton.clicked()
    else if (cursorColumn === 0) resetDraft()
    else if (cursorColumn === 1) mode = "clocks"
    else applySettings()
  }

  function activateCursor() {
    if (!cursorActive) return
    if (focusSection === "tabs") activateTab()
    else activateBody()
  }

  function setTabCursor(index) {
    cursorActive = true
    focusSection = "tabs"
    tabIndex = index
  }

  readonly property var configuredLocations: Model.sanitizeLocations(
    setting("locations", []),
    timezoneService.validZones.length > 1 ? timezoneService.validZones : null,
    timezoneService.systemTimezone)
  readonly property string hourFormat: String(setting("hourFormat", "24")) === "12" ? "12" : "24"
  readonly property bool showAbbreviation: setting("showAbbreviation", true) !== false
  readonly property bool showUtcOffset: setting("showUtcOffset", false) === true
  readonly property bool showTodayDate: setting("showTodayDate", false) === true
  readonly property string systemDate: Qt.formatDateTime(new Date(), "yyyy-MM-dd")

  function open() {
    if (!durableSettingsLoaded) {
      pendingOpen = true
      return
    }
    mode = "clocks"
    cursorActive = false
    tabIndex = 0
    focusSection = "tabs"
    timezoneService.locations = configuredLocations
    timezoneService.refresh()
    controller.show()
  }

  function close() { controller.hide() }
  function toggle() { if (opened) close(); else open() }

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function")
      return bar.switchPanelFrom(barIdentity, direction)
    return false
  }

  function persistSettings(values) {
    var nextDurable = ({})
    for (var existing in durableSettings) nextDurable[existing] = durableSettings[existing]
    for (var key in values) nextDurable[key] = values[key]
    durableSettings = nextDurable
    durableSettingsLoaded = true
    saveDurableSettings(nextDurable)
  }

  function enterSettings() {
    draftLocations = Model.cloneLocations(configuredLocations)
    settingsError = ""
    resetArmed = false
    formatButton.active = hourFormat === "12"
    abbreviationButton.active = showAbbreviation
    offsetButton.active = showUtcOffset
    todayDateButton.active = showTodayDate
    mode = "settings"
  }

  function replaceDraft(next) { draftLocations = Model.cloneLocations(next) }

  function addDraftLocation() {
    var timezone = newLocationTimezone
    if (timezoneService.validZones.indexOf(timezone) === -1) {
      settingsError = "Select a valid timezone."
      return
    }
    var label = addLabel.text.trim() || Model.defaultLabelForTimezone(timezone)
    if (draftLocations.length >= 20) {
      settingsError = "A maximum of 20 locations is supported."
      return
    }
    var next = Model.cloneLocations(draftLocations)
    next.push({ label: label, timezone: timezone })
    replaceDraft(next)
    addLabel.text = ""
    newLocationTimezone = "UTC"
    settingsError = ""
  }

  function removeDraft(index) {
    var next = Model.cloneLocations(draftLocations)
    next.splice(index, 1)
    replaceDraft(next)
  }

  function moveDraft(index, delta) {
    var target = index + delta
    if (target < 0 || target >= draftLocations.length) return
    var next = Model.cloneLocations(draftLocations)
    var value = next.splice(index, 1)[0]
    next.splice(target, 0, value)
    replaceDraft(next)
  }

  function updateDraft(index, label, timezone) {
    if (index < 0 || index >= draftLocations.length) return
    var next = Model.cloneLocations(draftLocations)
    next[index].label = String(label || "").trim()
    next[index].timezone = String(timezone || "").trim()
    replaceDraft(next)
  }

  function applySettings() {
    var sanitized = Model.sanitizeLocations(draftLocations, timezoneService.validZones)
    if (draftLocations.length === 0 || sanitized.length !== draftLocations.length) {
      settingsError = "Every location must have a valid label and IANA timezone."
      return
    }
    persistSettings({
      locations: sanitized,
      hourFormat: formatButton.active ? "12" : "24",
      showAbbreviation: abbreviationButton.active,
      showUtcOffset: offsetButton.active,
      showTodayDate: todayDateButton.active
    })
    timezoneService.locations = sanitized
    timezoneService.refresh()
    mode = "clocks"
  }

  function resetDraft() {
    if (!resetArmed) {
      resetArmed = true
      settingsError = "Choose Reset again to load safe defaults. Nothing is saved until Apply."
      return
    }
    replaceDraft(Model.defaultLocations(timezoneService.systemTimezone))
    resetArmed = false
    settingsError = "Defaults loaded. Choose Apply to save them."
  }

  function enterConverter() {
    converterSource = timezoneService.systemTimezone || "UTC"
    conversionDate.text = Qt.formatDateTime(new Date(), "yyyy-MM-dd")
    conversionTime.text = Qt.formatDateTime(new Date(), "HH:mm")
    mode = "convert"
  }

  function fillNow() {
    timezoneService.sourceNow(converterSource, function(result) {
      if (!result) return
      conversionDate.text = result.date
      conversionTime.text = result.time24
    })
  }

  function runConversion() {
    timezoneService.convert(converterSource, conversionDate.text.trim(),
      conversionTime.text.trim(), configuredLocations)
  }

  TimezoneService {
    id: timezoneService
    locations: root.configuredLocations
    active: root.opened
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(500))
    contentHeight: panel.fittedContentHeight(Math.min(content.implicitHeight, Style.space(720)))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editorActive || converterTimezone.popupOpen || addTimezone.popupOpen
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: content
          width: parent.width
          spacing: Style.space(12)

          PanelHero {
            title: "World Clock"
            meta: root.mode === "clocks" ? "LOCAL TIME EVERYWHERE" : root.mode.toUpperCase()
            detail: root.configuredLocations.length + " locations"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            iconComponent: Component {
              Text {
                text: "󰖟"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(6)

            Button {
              width: (parent.width - parent.spacing * 2) / 3
              text: "Clocks"
              foreground: root.contentForeground
              bordered: true
              active: root.mode === "clocks"
              hasCursor: root.cursorActive && root.focusSection === "tabs" && root.tabIndex === 0
              onHovered: function(hovered) { if (hovered) root.setTabCursor(0) }
              onClicked: root.mode = "clocks"
            }
            Button {
              width: (parent.width - parent.spacing * 2) / 3
              text: "Convert"
              foreground: root.contentForeground
              bordered: true
              active: root.mode === "convert"
              hasCursor: root.cursorActive && root.focusSection === "tabs" && root.tabIndex === 1
              onHovered: function(hovered) { if (hovered) root.setTabCursor(1) }
              onClicked: root.enterConverter()
            }
            Button {
              width: (parent.width - parent.spacing * 2) / 3
              text: "Settings"
              foreground: root.contentForeground
              bordered: true
              active: root.mode === "settings"
              hasCursor: root.cursorActive && root.focusSection === "tabs" && root.tabIndex === 2
              onHovered: function(hovered) { if (hovered) root.setTabCursor(2) }
              onClicked: root.enterSettings()
            }
          }

          PanelSeparator { foreground: root.contentForeground }

          Column {
            width: parent.width
            spacing: Style.space(5)
            visible: root.mode === "clocks"

            Repeater {
              model: root.configuredLocations

              Column {
                required property var modelData
                required property int index
                width: parent.width
                spacing: Style.space(2)
                readonly property var clockResult: timezoneService.times[modelData.timezone]

                Row {
                  width: parent.width
                  Text {
                    width: parent.width * 0.48
                    text: modelData.label
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }
                  Text {
                    width: parent.width * 0.30
                    text: Model.formatClock(parent.parent.clockResult, root.hourFormat)
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.subtitle
                    font.bold: true
                    horizontalAlignment: Text.AlignRight
                  }
                  Text {
                    width: parent.width * 0.22
                    text: {
                      var parts = []
                      if (root.showAbbreviation && parent.parent.clockResult) parts.push(parent.parent.clockResult.abbreviation)
                      if (root.showUtcOffset && parent.parent.clockResult) parts.push(Model.formatOffset(parent.parent.clockResult.offset))
                      return parts.join(" · ")
                    }
                    color: root.contentForeground
                    opacity: 0.65
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    horizontalAlignment: Text.AlignRight
                  }
                }
                Text {
                  text: clockResult
                    ? Model.relativeDay(root.systemDate, clockResult.date, root.showTodayDate) + " · " + modelData.timezone
                    : "Waiting for " + modelData.timezone
                  color: root.contentForeground
                  opacity: 0.55
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }
                PanelSeparator {
                  width: parent.width
                  foreground: root.contentForeground
                  visible: index < root.configuredLocations.length - 1
                }
              }
            }

          }

          Column {
            width: parent.width
            spacing: Style.space(8)
            visible: root.mode === "convert"

            PanelSectionHeader {
              text: "SOURCE TIMEZONE"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
            }
            SearchableDropdown {
              id: converterTimezone
              width: parent.width
              label: "Timezone"
              value: root.converterSource
              options: timezoneService.timezoneOptions
              placeholderText: "Search city, country, or timezone…"
              popupMinHeight: Style.space(120)
              popupRowHeight: Math.max(Style.spacing.popupRowHeight, Style.space(40))
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              hasCursor: root.cursorActive && root.focusSection === "body" && root.mode === "convert" && root.cursorRow === 0
              onHovered: function(hovered) { if (hovered) root.setBodyCursor(0, 0) }
              onChanged: function(value) { root.converterSource = value }
            }
            Row {
              width: parent.width
              spacing: Style.space(8)
              TextField {
                id: conversionDate
                width: (parent.width - parent.spacing) * 0.58
                placeholderText: "YYYY-MM-DD"
                foreground: root.contentForeground
                hasCursor: root.cursorActive && root.focusSection === "body" && root.mode === "convert" && root.cursorRow === 1 && root.cursorColumn === 0
                onHoveredChanged: if (hovered) root.setBodyCursor(1, 0)
                onActiveFocusChanged: root.editorActive = activeFocus
                Keys.onEscapePressed: root.finishEditing()
                Keys.onReturnPressed: root.finishEditing()
              }
              TextField {
                id: conversionTime
                width: (parent.width - parent.spacing) * 0.42
                placeholderText: "HH:MM"
                foreground: root.contentForeground
                hasCursor: root.cursorActive && root.focusSection === "body" && root.mode === "convert" && root.cursorRow === 1 && root.cursorColumn === 1
                onHoveredChanged: if (hovered) root.setBodyCursor(1, 1)
                onActiveFocusChanged: root.editorActive = activeFocus
                Keys.onEscapePressed: root.finishEditing()
                Keys.onReturnPressed: root.finishEditing()
              }
            }
            Row {
              width: parent.width
              spacing: Style.space(8)
              Button {
                id: nowButton
                width: (parent.width - parent.spacing) / 2
                text: "Now"
                foreground: root.contentForeground
                bordered: true
                hasCursor: root.cursorActive && root.focusSection === "body" && root.mode === "convert" && root.cursorRow === 2 && root.cursorColumn === 0
                onHovered: function(hovered) { if (hovered) root.setBodyCursor(2, 0) }
                onClicked: root.fillNow()
              }
              Button {
                id: convertButton
                width: (parent.width - parent.spacing) / 2
                text: timezoneService.converting ? "Converting…" : "Convert"
                foreground: root.contentForeground
                bordered: true
                enabled: !timezoneService.converting
                hasCursor: root.cursorActive && root.focusSection === "body" && root.mode === "convert" && root.cursorRow === 2 && root.cursorColumn === 1
                onHovered: function(hovered) { if (hovered) root.setBodyCursor(2, 1) }
                onClicked: root.runConversion()
              }
            }
            Text {
              visible: timezoneService.conversionError !== ""
              width: parent.width
              text: timezoneService.conversionError
              color: root.contentForeground
              opacity: 0.75
              wrapMode: Text.Wrap
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              visible: timezoneService.conversionWarning !== ""
              width: parent.width
              text: timezoneService.conversionWarning
              color: root.contentForeground
              opacity: 0.75
              wrapMode: Text.Wrap
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
            }
            PanelSeparator {
              visible: timezoneService.conversionResults.length > 0
              foreground: root.contentForeground
            }
            Repeater {
              model: timezoneService.conversionResults
              Column {
                required property var modelData
                required property int index
                width: parent.width
                spacing: Style.space(2)
                Row {
                  width: parent.width
                  visible: modelData.result !== null
                  Text {
                    width: parent.width * 0.48
                    text: modelData.label
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }
                  Text {
                    width: parent.width * 0.30
                    text: Model.formatClock(modelData.result, root.hourFormat)
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.subtitle
                    font.bold: true
                    horizontalAlignment: Text.AlignRight
                  }
                  Text {
                    width: parent.width * 0.22
                    text: root.showAbbreviation ? modelData.result.abbreviation : ""
                    color: root.contentForeground
                    opacity: 0.65
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    horizontalAlignment: Text.AlignRight
                  }
                }
                Text {
                  width: parent.width
                  visible: modelData.result !== null
                  text: modelData.result
                    ? modelData.result.weekday + " " + modelData.result.date
                      + " · " + Model.conversionDay(timezoneService.conversionSourceDate, modelData.result.date)
                    : ""
                  color: root.contentForeground
                  opacity: 0.55
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }
                Text {
                  width: parent.width
                  visible: modelData.result === null
                  text: modelData.label + " · " + modelData.error
                  color: root.contentForeground
                  opacity: 0.75
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.Wrap
                }
                PanelSeparator {
                  width: parent.width
                  foreground: root.contentForeground
                  visible: index < timezoneService.conversionResults.length - 1
                }
              }
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(8)
            visible: root.mode === "settings"

            PanelSectionHeader {
              text: "LOCATIONS"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
            }
            Row {
              width: parent.width
              spacing: Style.space(6)
              readonly property real actionsWidth: Style.space(22) * 3
              readonly property real fieldsWidth: width - actionsWidth - spacing * 4
              Text {
                width: parent.fieldsWidth * 0.58
                text: "TIMEZONE"
                color: root.contentForeground
                opacity: 0.55
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                width: parent.fieldsWidth * 0.42
                text: "ALIAS"
                color: root.contentForeground
                opacity: 0.55
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
              }
            }
            Repeater {
              id: locationRepeater
              model: root.draftLocations
              Column {
                required property var modelData
                required property int index
                width: parent.width
                spacing: Style.space(5)
                function activateColumn(column) {
                  if (column === 0) draftLabel.forceActiveFocus()
                  else if (column === 1 && upButton.enabled) root.moveDraft(index, -1)
                  else if (column === 2 && downButton.enabled) root.moveDraft(index, 1)
                  else if (column === 3) root.removeDraft(index)
                }
                Row {
                  width: parent.width
                  spacing: Style.space(5)
                  readonly property real actionsWidth: Style.space(22) * 3
                  readonly property real fieldsWidth: width - actionsWidth - spacing * 4
                  Text {
                    width: parent.fieldsWidth * 0.58
                    height: draftLabel.height
                    text: modelData.timezone
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideMiddle
                  }
                  TextField {
                    id: draftLabel
                    width: parent.fieldsWidth * 0.42
                    text: modelData.label
                    placeholderText: "Alias"
                    foreground: root.contentForeground
                    hasCursor: root.cursorActive && root.focusSection === "body" && root.mode === "settings" && root.cursorRow === index && root.cursorColumn === 0
                    onHoveredChanged: if (hovered) root.setBodyCursor(index, 0)
                    onActiveFocusChanged: root.editorActive = activeFocus
                    Keys.onEscapePressed: root.finishEditing()
                    Keys.onReturnPressed: {
                      root.updateDraft(index, text, modelData.timezone)
                      root.finishEditing()
                    }
                    onEditingFinished: root.updateDraft(index, text, modelData.timezone)
                  }
                  PanelActionButton { id: upButton; iconText: ""; tooltipText: "Move up"; enabled: index > 0; hasCursor: root.cursorActive && root.focusSection === "body" && root.mode === "settings" && root.cursorRow === index && root.cursorColumn === 1; onHovered: function(hovered) { if (hovered) root.setBodyCursor(index, 1) }; onClicked: root.moveDraft(index, -1) }
                  PanelActionButton { id: downButton; iconText: ""; tooltipText: "Move down"; enabled: index < root.draftLocations.length - 1; hasCursor: root.cursorActive && root.focusSection === "body" && root.mode === "settings" && root.cursorRow === index && root.cursorColumn === 2; onHovered: function(hovered) { if (hovered) root.setBodyCursor(index, 2) }; onClicked: root.moveDraft(index, 1) }
                  PanelActionButton { id: deleteButton; iconText: "󰆴"; tooltipText: "Remove"; hasCursor: root.cursorActive && root.focusSection === "body" && root.mode === "settings" && root.cursorRow === index && root.cursorColumn === 3; onHovered: function(hovered) { if (hovered) root.setBodyCursor(index, 3) }; onClicked: root.removeDraft(index) }
                }
                PanelSeparator { width: parent.width; foreground: root.contentForeground }
              }
            }
            Row {
              width: parent.width
              spacing: Style.space(6)
              SearchableDropdown {
                id: addTimezone
                width: parent.width * 0.60
                showLabel: false
                value: root.newLocationTimezone
                options: timezoneService.timezoneOptions
                placeholderText: "Search timezone…"
                popupMinHeight: Style.space(120)
                popupRowHeight: Math.max(Style.spacing.popupRowHeight, Style.space(40))
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                hasCursor: root.cursorActive && root.focusSection === "body" && root.mode === "settings" && root.cursorRow === root.draftLocations.length && root.cursorColumn === 0
                onHovered: function(hovered) { if (hovered) root.setBodyCursor(root.draftLocations.length, 0) }
                onChanged: function(value) { root.newLocationTimezone = value }
              }
              TextField {
                id: addLabel
                width: parent.width * 0.23
                placeholderText: "Alias"
                foreground: root.contentForeground
                hasCursor: root.cursorActive && root.focusSection === "body" && root.mode === "settings" && root.cursorRow === root.draftLocations.length && root.cursorColumn === 1
                onHoveredChanged: if (hovered) root.setBodyCursor(root.draftLocations.length, 1)
                onActiveFocusChanged: root.editorActive = activeFocus
                Keys.onEscapePressed: root.finishEditing()
                Keys.onReturnPressed: root.finishEditing()
              }
              Button {
                id: addButton
                width: parent.width - addTimezone.width - addLabel.width - parent.spacing * 2
                text: "Add"
                foreground: root.contentForeground
                bordered: true
                hasCursor: root.cursorActive && root.focusSection === "body" && root.mode === "settings" && root.cursorRow === root.draftLocations.length && root.cursorColumn === 2
                onHovered: function(hovered) { if (hovered) root.setBodyCursor(root.draftLocations.length, 2) }
                onClicked: root.addDraftLocation()
              }
            }

            PanelSeparator { foreground: root.contentForeground }
            PanelSectionHeader {
              text: "DISPLAY"
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
            }
            Button {
              id: formatButton
              width: parent.width
              text: active ? "12-hour time" : "24-hour time"
              foreground: root.contentForeground
              bordered: true
              active: root.hourFormat === "12"
              hasCursor: root.cursorActive && root.focusSection === "body" && root.mode === "settings" && root.cursorRow === root.draftLocations.length + 1
              onHovered: function(hovered) { if (hovered) root.setBodyCursor(root.draftLocations.length + 1, 0) }
              onClicked: active = !active
            }
            Button {
              id: abbreviationButton
              width: parent.width
              text: "Timezone abbreviation"
              foreground: root.contentForeground
              bordered: true
              active: root.showAbbreviation
              hasCursor: root.cursorActive && root.focusSection === "body" && root.mode === "settings" && root.cursorRow === root.draftLocations.length + 2
              onHovered: function(hovered) { if (hovered) root.setBodyCursor(root.draftLocations.length + 2, 0) }
              onClicked: active = !active
            }
            Button {
              id: offsetButton
              width: parent.width
              text: "UTC offset"
              foreground: root.contentForeground
              bordered: true
              active: root.showUtcOffset
              hasCursor: root.cursorActive && root.focusSection === "body" && root.mode === "settings" && root.cursorRow === root.draftLocations.length + 3
              onHovered: function(hovered) { if (hovered) root.setBodyCursor(root.draftLocations.length + 3, 0) }
              onClicked: active = !active
            }
            Button {
              id: todayDateButton
              width: parent.width
              text: "Full date for Today"
              foreground: root.contentForeground
              bordered: true
              active: root.showTodayDate
              hasCursor: root.cursorActive && root.focusSection === "body" && root.mode === "settings" && root.cursorRow === root.draftLocations.length + 4
              onHovered: function(hovered) { if (hovered) root.setBodyCursor(root.draftLocations.length + 4, 0) }
              onClicked: active = !active
            }
            Text {
              visible: root.settingsError !== ""
              width: parent.width
              text: root.settingsError
              color: root.contentForeground
              opacity: 0.7
              wrapMode: Text.Wrap
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Row {
              width: parent.width
              spacing: Style.space(6)
              Button { id: resetButton; width: (parent.width - parent.spacing * 2) / 3; text: root.resetArmed ? "Confirm reset" : "Reset"; foreground: root.contentForeground; bordered: true; hasCursor: root.cursorActive && root.focusSection === "body" && root.mode === "settings" && root.cursorRow === root.draftLocations.length + 5 && root.cursorColumn === 0; onHovered: function(hovered) { if (hovered) root.setBodyCursor(root.draftLocations.length + 5, 0) }; onClicked: root.resetDraft() }
              Button { id: cancelButton; width: (parent.width - parent.spacing * 2) / 3; text: "Cancel"; foreground: root.contentForeground; bordered: true; hasCursor: root.cursorActive && root.focusSection === "body" && root.mode === "settings" && root.cursorRow === root.draftLocations.length + 5 && root.cursorColumn === 1; onHovered: function(hovered) { if (hovered) root.setBodyCursor(root.draftLocations.length + 5, 1) }; onClicked: root.mode = "clocks" }
              Button { id: applyButton; width: (parent.width - parent.spacing * 2) / 3; text: "Apply"; foreground: root.contentForeground; bordered: true; hasCursor: root.cursorActive && root.focusSection === "body" && root.mode === "settings" && root.cursorRow === root.draftLocations.length + 5 && root.cursorColumn === 2; onHovered: function(hovered) { if (hovered) root.setBodyCursor(root.draftLocations.length + 5, 2) }; onClicked: root.applySettings() }
            }
          }
        }
      }
    }
  }
}
