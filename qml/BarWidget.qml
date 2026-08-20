import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import QtMultimedia
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "coak.omaloom"
  ipcTarget: "coak.omaloom"
  manageIpc: false

  readonly property string home: Quickshell.env("HOME")
  readonly property string recorder: home + "/.config/omarchy/plugins/coak.omaloom/bin/omaloom-recorder"
  readonly property string devicesHelper: home + "/.config/omarchy/plugins/coak.omaloom/bin/omaloom-devices"
  readonly property string folderPicker: home + "/.config/omarchy/plugins/coak.omaloom/bin/omaloom-folder-picker"
  readonly property string recordingsHelper: home + "/.config/omarchy/plugins/coak.omaloom/bin/omaloom-recordings"
  // Elm-ish model: state is owned by backend observations. The backend owns
  // source selection, then countdown, then gpu-screen-recorder startup.
  readonly property bool selecting: state === "selecting"
  readonly property bool preparing: state === "preparing"
  readonly property bool countdown: state === "countdown"
  readonly property bool starting: state === "starting"
  readonly property bool recording: state === "recording"
  readonly property bool busy: selecting || preparing || countdown || starting || recording
  readonly property bool canStart: !startDelay.running && !actionProcess.running && !busy
  readonly property bool setupResourcesActive: root.opened && !root.busy && root.state !== "error"
  readonly property bool previewActive: setupResourcesActive && omaloomSettings.recordWebcam && mediaDevices.videoInputs.length > 0
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  property bool interactive: true
  property bool pressable: true
  property bool concealed: false
  property string state: "idle"
  property string lastMessage: "Ready to record locally."
  property string lastSavedPath: ""
  property bool clickStatusSawRecording: false
  property int countdownRemaining: 5
  property var pendingStartArgs: []
  property var microphoneDevices: []
  property var webcamDevices: []
  property real microphoneLevel: 0
  property bool microphoneListOpen: false
  property bool webcamListOpen: false
  property bool guideActive: false
  property var currentGuide: null
  property bool reopenAfterFolderPicker: false
  property bool meterRestartPending: false
  property var previewOutputTarget: null
  property var recordings: []
  property bool recordingsLoading: false
  property string recordingsError: ""
  property string actionFeedback: ""
  property bool actionFeedbackError: false
  property string dashboardTab: "record"
  property string pendingRecordingAction: ""

  function refresh() {
    if (statusProcess.running) return
    statusProcess.command = [recorder, "status"]
    statusProcess.running = true
  }

  function triggerPress(mouseButton) {
    // Once a recording is starting or active, the Omaloom bar widget is an
    // indicator only. Do not open a popup over the capture and do not race the
    // built-in Omarchy stop control. Stop is handled by Omarchy's top-center
    // recording button for v1.
    if (root.busy) {
      root.refresh()
      return
    }

    if (mouseButton === Qt.RightButton) {
      root.refresh()
      return
    }

    // Local state can be stale across per-monitor bar instances. Before opening
    // the popup, ask the backend whether Omarchy is actually recording. If it
    // is, update to REC and keep the popup closed.
    if (clickStatusProcess.running) return
    clickStatusSawRecording = false
    clickStatusProcess.command = [recorder, "status"]
    clickStatusProcess.running = true
  }

  function startRecording() {
    if (!canStart) return
    var args = [recorder, "start", "--directory", omaloomSettings.outputDirectory]
    if (omaloomSettings.recordFullscreen) args.push("--fullscreen")
    if (omaloomSettings.recordSystemAudio) args.push("--desktop-audio")
    if (omaloomSettings.recordMicrophone) {
      args.push("--microphone")
      if (omaloomSettings.microphoneDevice !== "") args.push("--microphone-device", omaloomSettings.microphoneDevice)
    }
    if (omaloomSettings.recordWebcam) {
      args.push("--webcam")
      if (omaloomSettings.webcamDevice !== "") args.push("--webcam-device", omaloomSettings.webcamDevice)
      args.push("--webcam-position", omaloomSettings.webcamPosition)
      args.push("--webcam-size", omaloomSettings.webcamSize)
    }
    lastMessage = omaloomSettings.recordFullscreen ? "Preparing current-monitor recording…" : "Preparing source selector…"
    lastSavedPath = ""
    hideRegionGuide()
    pendingStartArgs = args
    countdownRemaining = 5
    state = omaloomSettings.recordFullscreen ? "preparing" : "selecting"
    // Close first and launch on a short timer so the popup has a frame to
    // unmap before slurp/source selection begins. The backend owns the real
    // sequence: source selection, then countdown, then gpu-screen-recorder.
    root.close()
    startDelay.restart()
  }

  function launchPendingRecording() {
    actionProcess.command = pendingStartArgs
    actionProcess.running = true
    startRefreshDelay.restart()
  }

  function openFolderPicker() {
    if (folderPickerProcess.running || !canStart) return
    // The external portal window takes focus, so KeyboardPanel dismisses the
    // setup popup. Restore it after selection/cancellation to keep the user in
    // the same setup flow.
    reopenAfterFolderPicker = true
    folderPickerProcess.command = [folderPicker, "--current", omaloomSettings.outputDirectory]
    folderPickerProcess.running = true
  }

  function hideRegionGuide() {
    guideActive = false
    currentGuide = null
  }

  function maybeShowRegionGuide(event) {
    if (event && event.guide && event.guide.type === "region") {
      currentGuide = event.guide
      guideActive = true
    } else {
      hideRegionGuide()
    }
  }

  function formatBytes(size) {
    var n = Number(size || 0)
    if (n >= 1073741824) return (n / 1073741824).toFixed(1) + " GB"
    if (n >= 1048576) return (n / 1048576).toFixed(1) + " MB"
    if (n >= 1024) return Math.round(n / 1024) + " KB"
    return n + " B"
  }

  function formatModified(seconds) {
    var d = new Date(Number(seconds || 0) * 1000)
    if (isNaN(d.getTime())) return ""
    return d.toLocaleString(Qt.locale(), Locale.ShortFormat)
  }

  function recordingMeta(item) {
    if (!item) return ""
    return formatModified(item.modified) + " · " + formatBytes(item.size)
  }

  function refreshRecordings() {
    if (recordingsProcess.running || busy) return
    recordingsLoading = true
    recordingsError = ""
    recordingsProcess.command = [recordingsHelper, "list", "--directory", omaloomSettings.outputDirectory, "--limit", "0"]
    recordingsProcess.running = true
  }

  function runRecordingAction(action, path) {
    if (recordingActionProcess.running || busy || recordingsLoading || !path) return
    actionFeedback = ""
    actionFeedbackError = false
    recordingsError = ""
    pendingRecordingAction = action
    recordingActionProcess.command = [recordingsHelper, action, path]
    recordingActionProcess.running = true
  }

  function actionLabel(action) {
    if (action === "copy-path") return "Copied path"
    if (action === "reveal") return "Revealing recording"
    if (action === "open") return "Opening recording"
    return "Done"
  }

  function refreshDevices() {
    microphoneListProcess.command = [devicesHelper, "list-microphones"]
    webcamListProcess.command = [devicesHelper, "list-webcams"]
    microphoneListProcess.running = true
    webcamListProcess.running = true
  }

  function parseDeviceList(line, fallback) {
    try {
      var devices = JSON.parse(String(line || "[]"))
      return Array.isArray(devices) ? devices : fallback
    } catch (e) {
      console.warn("Omaloom device list parse failed:", e)
      return fallback
    }
  }

  function deviceLabel(devices, id, fallback) {
    for (var i = 0; i < devices.length; i++) {
      if (devices[i].id === id) return devices[i].label || devices[i].id
    }
    if (id !== "") return fallback + " (disconnected)"
    return fallback
  }

  function optionLabel(value) {
    var words = String(value || "").split("-")
    for (var i = 0; i < words.length; i++) words[i] = words[i].charAt(0).toUpperCase() + words[i].slice(1)
    return words.join(" ")
  }

  function cycleWebcamPosition() {
    var values = ["top-left", "top-right", "bottom-left", "bottom-right"]
    var i = values.indexOf(omaloomSettings.webcamPosition)
    omaloomSettings.webcamPosition = values[(i + 1) % values.length]
  }

  function cycleWebcamSize() {
    var values = ["small", "medium", "large"]
    var i = values.indexOf(omaloomSettings.webcamSize)
    omaloomSettings.webcamSize = values[(i + 1) % values.length]
  }

  function compositionAspect() {
    return popup && popup.screen && popup.screen.width > 0 && popup.screen.height > 0 ? popup.screen.width / popup.screen.height : 16 / 9
  }

  function webcamPreviewScale() {
    if (omaloomSettings.webcamSize === "small") return 0.18
    if (omaloomSettings.webcamSize === "large") return 0.3375
    return 0.25
  }

  function cycleDevice(kind) {
    var devices = kind === "microphone" ? microphoneDevices : webcamDevices
    if (devices.length === 0) return
    var current = kind === "microphone" ? omaloomSettings.microphoneDevice : omaloomSettings.webcamDevice
    var currentIndex = -1
    for (var i = 0; i < devices.length; i++) if (devices[i].id === current) currentIndex = i
    var next = devices[(currentIndex + 1) % devices.length].id
    if (kind === "microphone") omaloomSettings.microphoneDevice = next
    else omaloomSettings.webcamDevice = next
  }

  function selectedCameraDevice() {
    var inputs = mediaDevices.videoInputs
    var fallback = inputs.length > 0 ? inputs[0] : null
    var selected = omaloomSettings.webcamDevice
    for (var i = 0; i < inputs.length; i++) {
      if (String(inputs[i].id) === selected || String(inputs[i].description).indexOf(deviceLabel(webcamDevices, selected, "")) !== -1)
        return inputs[i]
    }
    return fallback
  }

  function updateMeter() {
    var shouldRun = root.setupResourcesActive && omaloomSettings.recordMicrophone
    if (shouldRun && !meterProcess.running) {
      microphoneLevel = 0
      meterProcess.command = [devicesHelper, "meter", omaloomSettings.microphoneDevice || "default_input"]
      meterProcess.running = true
    } else if (!shouldRun && meterProcess.running) {
      meterRestartPending = false
      meterProcess.running = false
      microphoneLevel = 0
    }
  }

  function restartMeterForSelectedDevice() {
    microphoneLevel = 0
    if (meterProcess.running) {
      // Wait for the old process's exit callback before starting the new
      // source. Otherwise that callback can zero a newly started meter.
      meterRestartPending = true
      meterProcess.running = false
    } else {
      meterRestartPending = false
      meterRestartDelay.restart()
    }
  }

  function extractJsonString(text, key) {
    var re = new RegExp('"' + key + '":"([^"]*)"')
    var match = String(text || "").match(re)
    if (!match) return ""
    return match[1].replace(/\\n/g, "\n").replace(/\\t/g, "\t").replace(/\\r/g, "\r").replace(/\\"/g, '"').replace(/\\\\/g, "\\")
  }

  function updateFromLine(line) {
    var text = String(line || "")
    if (text === "") return
    var event = null
    try { event = JSON.parse(text) } catch (e) { event = null }
    lastMessage = text

    if (text.indexOf('"source_selected"') !== -1) {
      state = "preparing"
      countdownRemaining = 5
      maybeShowRegionGuide(event)
      lastMessage = omaloomSettings.recordWebcam ? "Preparing webcam overlay…" : "Preparing recording…"
      root.open()
      startTimeout.restart()
    } else if (text.indexOf('"countdown"') !== -1) {
      var seconds = extractJsonString(text, "seconds")
      countdownRemaining = parseInt(seconds || "0")
      state = "countdown"
      lastMessage = "Recording starts in " + seconds + "…"
    } else if (text.indexOf('"event":"starting"') !== -1) {
      state = "starting"
      lastMessage = "Starting recording…"
      root.close()
      root.controller.hide()
    } else if (text.indexOf('"recording_started"') !== -1) {
      state = "recording"
      var startedPath = extractJsonString(text, "path")
      lastMessage = startedPath ? "Recording: " + startedPath : "Recording…"
    } else if (text.indexOf('"cancelled"') !== -1) {
      state = "idle"
      hideRegionGuide()
      lastMessage = "Selection cancelled. Ready to record locally."
    } else if (text.indexOf('"saved"') !== -1) {
      lastSavedPath = extractJsonString(text, "path")
      hideRegionGuide()
      state = "saved"
      lastMessage = lastSavedPath ? "Saved: " + lastSavedPath : "Recording saved."
      recordingsRefreshDelay.restart()
    } else if (text.indexOf('"state":"recording"') !== -1) {
      state = "recording"
      var activePath = extractJsonString(text, "path")
      lastMessage = activePath ? "Recording: " + activePath : "Recording…"
    } else if (text.indexOf('"state":"idle"') !== -1) {
      if (state === "selecting" || state === "preparing" || state === "countdown" || state === "starting") {
        // During source selection/countdown gpu-screen-recorder does not exist
        // yet. Keep the UI in its local state until it becomes recording,
        // cancelled, or the timeout resets.
        return
      }
      if (state === "recording") {
        hideRegionGuide()
        state = "idle"
        lastMessage = "Recording stopped. Ready to record locally."
        recordingsRefreshDelay.restart()
      } else if (state !== "saved") {
        hideRegionGuide()
        state = "idle"
        lastMessage = lastSavedPath ? "Last saved: " + lastSavedPath : "Ready to record locally."
      }
    } else if (text.indexOf('"error"') !== -1) {
      hideRegionGuide()
      state = "error"
      var message = extractJsonString(text, "message")
      lastMessage = message || text
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    if (opened) {
      refreshDevices()
      restartMeterForSelectedDevice()
      dashboardTab = "record"
      if (!busy) refreshRecordings()
    } else {
      microphoneLevel = 0
      microphoneListOpen = false
      webcamListOpen = false
      updateMeter()
    }
  }
  onBusyChanged: updateMeter()
  onStateChanged: updateMeter()

  OmaloomRegionGuide {
    active: root.guideActive
    guide: root.currentGuide
    accent: Color.accent
  }

  OmaloomSettings {
    id: omaloomSettings
    onRecordMicrophoneChanged: root.updateMeter()
    onMicrophoneDeviceChanged: root.restartMeterForSelectedDevice()
    onOutputDirectoryChanged: {
      root.recordings = []
      root.recordingsError = ""
      if (root.opened && !root.busy) root.refreshRecordings()
    }
  }

  MediaDevices { id: mediaDevices }

  // QCamera can retain /dev/video* even when Camera.active is false. Create
  // and destroy the entire capture graph with the setup popup so mpv can
  // acquire the webcam for the actual recording overlay.
  Loader {
    id: previewSessionLoader
    active: root.previewActive
    sourceComponent: Component {
      Item {
        Camera {
          id: previewCamera
          active: true
          cameraDevice: root.selectedCameraDevice()
        }
        CaptureSession {
          camera: previewCamera
          videoOutput: root.previewOutputTarget
        }
      }
    }
  }

  Component.onCompleted: {
    refresh()
    refreshDevices()
  }
  Component.onDestruction: {
    hideRegionGuide()
    reopenAfterFolderPicker = false
    if (folderPickerProcess.running) folderPickerProcess.running = false
    if (meterProcess.running) meterProcess.running = false
    previewSessionLoader.active = false
  }
  Timer {
    interval: root.guideActive ? 250 : (root.busy ? 1000 : 3000)
    repeat: true
    running: true
    onTriggered: root.refresh()
  }

  Timer {
    id: recordingsRefreshDelay
    interval: 1400
    repeat: false
    onTriggered: if (root.opened && !root.busy) root.refreshRecordings()
  }

  Timer {
    id: meterRestartDelay
    interval: 100
    repeat: false
    onTriggered: root.updateMeter()
  }

  Timer {
    id: reopenAfterPickerDelay
    interval: 150
    repeat: false
    onTriggered: {
      if (root.reopenAfterFolderPicker && !root.busy) root.open()
      root.reopenAfterFolderPicker = false
    }
  }

  Timer {
    id: startDelay
    interval: 200
    repeat: false
    onTriggered: root.launchPendingRecording()
  }

  Timer {
    id: startRefreshDelay
    interval: 1200
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: startTimeout
    interval: 30000
    repeat: false
    onTriggered: {
      if (root.state === "selecting" || root.state === "preparing" || root.state === "countdown" || root.state === "starting") {
        root.hideRegionGuide()
        root.state = "idle"
        root.lastMessage = "Recording was not started. Ready to record locally."
        root.refresh()
      }
    }
  }

  Process {
    id: folderPickerProcess
    stdout: SplitParser {
      onRead: function(line) {
        try {
          var result = JSON.parse(String(line || "{}"))
          if (typeof result.path === "string" && result.path !== "") omaloomSettings.outputDirectory = result.path
        } catch (e) {
          console.warn("Omaloom folder picker returned invalid JSON:", e)
        }
      }
    }
    stderr: SplitParser { onRead: function(line) { console.warn("Omaloom folder picker failed:", String(line)) } }
    onExited: function() { reopenAfterPickerDelay.restart() }
  }

  Process {
    id: recordingsProcess
    stdout: SplitParser {
      onRead: function(line) {
        try {
          var payload = JSON.parse(String(line || "{}"))
          root.recordings = Array.isArray(payload.recordings) ? payload.recordings : []
          root.recordingsError = ""
        } catch (e) {
          root.recordings = []
          root.recordingsError = "Could not read recordings."
        }
      }
    }
    stderr: SplitParser {
      onRead: function(line) {
        try { root.recordingsError = JSON.parse(String(line || "{}")).error || String(line) }
        catch (e) { root.recordingsError = String(line) }
      }
    }
    onExited: function(exitCode) {
      root.recordingsLoading = false
      if (exitCode !== 0 && root.recordingsError === "") root.recordingsError = "Could not read recordings."
    }
  }

  Process {
    id: recordingActionProcess
    stdout: SplitParser {
      onRead: function(line) {
        try {
          var payload = JSON.parse(String(line || "{}"))
          if (payload.ok === true) {
            root.actionFeedback = root.actionLabel(payload.action || root.pendingRecordingAction)
            root.actionFeedbackError = false
          }
        } catch (e) {
          root.actionFeedback = "Done"
          root.actionFeedbackError = false
        }
      }
    }
    stderr: SplitParser {
      onRead: function(line) {
        root.actionFeedbackError = true
        try { root.actionFeedback = JSON.parse(String(line || "{}")).error || String(line) }
        catch (e) { root.actionFeedback = String(line) }
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.actionFeedback === "") {
        root.actionFeedback = "Recording action failed."
        root.actionFeedbackError = true
      }
      root.pendingRecordingAction = ""
      if (root.opened && !root.busy) root.refreshRecordings()
    }
  }

  Process {
    id: microphoneListProcess
    stdout: SplitParser { onRead: function(line) { root.microphoneDevices = root.parseDeviceList(line, []) } }
  }

  Process {
    id: webcamListProcess
    stdout: SplitParser { onRead: function(line) { root.webcamDevices = root.parseDeviceList(line, []) } }
  }

  Process {
    id: meterProcess
    stdout: SplitParser {
      onRead: function(line) {
        try { root.microphoneLevel = Math.max(0, Math.min(1, JSON.parse(String(line || "{}")).level || 0)) }
        catch (e) { root.microphoneLevel = 0 }
      }
    }
    onExited: function() {
      root.microphoneLevel = 0
      if (root.meterRestartPending) {
        root.meterRestartPending = false
        meterRestartDelay.restart()
      } else if (root.setupResourcesActive && omaloomSettings.recordMicrophone) {
        // Recover from a transient source disconnect or ffmpeg failure.
        meterRestartDelay.restart()
      }
    }
  }

  Process {
    id: clickStatusProcess
    stdout: SplitParser {
      onRead: function(line) {
        if (String(line || "").indexOf('"state":"recording"') !== -1)
          root.clickStatusSawRecording = true
      }
    }
    onExited: function(exitCode) {
      if (root.clickStatusSawRecording) {
        root.state = "recording"
        root.lastMessage = "Recording… Use the Omarchy stop button at the top center to finish."
        root.close()
      } else {
        root.toggle()
      }
    }
  }

  Process {
    id: statusProcess
    stdout: SplitParser { onRead: function(line) { root.updateFromLine(line) } }
  }

  Process {
    id: actionProcess
    stdout: SplitParser { onRead: function(line) { root.updateFromLine(line) } }
    stderr: SplitParser { onRead: function(line) { root.hideRegionGuide(); root.lastMessage = String(line); root.state = "error" } }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.state !== "error" && root.state !== "idle") {
        root.hideRegionGuide()
        root.state = "error"
        root.lastMessage = "Recorder start exited with code " + exitCode
      } else {
        root.refresh()
      }
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.countdown ? String(root.countdownRemaining) : (root.starting ? "GO" : (root.recording ? "REC" : "󰿎"))
    fontSize: (!root.countdown && !root.starting && !root.recording) ? Style.font.title : Style.font.body
    active: root.recording || root.countdown || root.starting
    tooltipText: root.recording ? "Recording — use the Omarchy stop button at the top center" : (root.countdown ? "Recording starts in " + root.countdownRemaining : (root.selecting ? "Select a source/region" : (root.preparing ? "Preparing recording…" : (root.starting ? "Starting recording…" : "Open Omaloom"))))
    labelVisible: !(root.bar && root.bar.vertical === true)
    hasVisualContent: true
    horizontalMargin: (!root.countdown && !root.starting && !root.recording) ? 7.25 : 8.75
    verticalPadding: 8.75

    onPressed: function(mouseButton) { root.triggerPress(mouseButton) }

    Text {
      visible: root.bar && root.bar.vertical === true
      anchors.centerIn: parent
      text: root.countdown ? String(root.countdownRemaining) : (root.starting ? "▶" : (root.recording ? "●" : "󰿎"))
      color: root.recording ? Color.urgent : button.foreground
      font.family: button.fontFamily
      font.pixelSize: (!root.countdown && !root.starting && !root.recording) ? button.fontSize * 1.12 : button.fontSize
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    centerOnBar: true
    readonly property bool narrowDashboard: contentWidth < Style.space(760)

    contentWidth: popup.fittedContentWidth(root.countdown ? Style.space(460) : Style.space(920))
    contentHeight: popup.fittedContentHeight(root.countdown ? Style.space(360) : Style.space(800), Style.space(840))

    Item {
      id: dashboardRoot
      anchors.fill: parent

      Column {
        id: countdownPane
        visible: root.countdown
        anchors.centerIn: parent
        width: parent.width
        spacing: Style.space(14)

        Text {
          width: parent.width
          text: "Recording starts in"
          color: root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.title
          font.bold: true
          horizontalAlignment: Text.AlignHCenter
        }

        Text {
          width: parent.width
          text: String(root.countdownRemaining)
          color: Color.accent
          font.family: root.contentFontFamily
          font.pixelSize: Style.space(150)
          font.bold: true
          horizontalAlignment: Text.AlignHCenter
        }

        Text {
          width: parent.width
          text: "Keep the selected area clear. Recording begins after countdown."
          color: Qt.darker(root.contentForeground, 1.45)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.Wrap
        }
      }

      Column {
        id: dashboard
        visible: !root.countdown
        anchors.fill: parent
        spacing: Style.space(12)

        Row {
          width: parent.width
          height: titleBlock.implicitHeight
          spacing: Style.space(12)

          Column {
            id: titleBlock
            width: parent.width - statusText.width - parent.spacing
            spacing: Style.space(2)

            Text {
              width: parent.width
              text: "Omaloom"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              width: parent.width
              text: root.recording ? "Recording" : (root.preparing ? "Preparing…" : (root.starting ? "Starting…" : "Local screen recording"))
              color: Qt.darker(root.contentForeground, 1.35)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }
          }

          Text {
            id: statusText
            anchors.verticalCenter: parent.verticalCenter
            text: root.recording ? "REC" : (root.preparing ? "PREP" : (root.starting ? "GO" : (root.recordingsLoading ? "SYNC" : "READY")))
            color: root.recording ? Color.urgent : root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }
        }

        Row {
          visible: popup.narrowDashboard
          height: visible ? Style.space(34) : 0
          width: parent.width
          spacing: Style.space(8)

          DashboardTabButton { label: "Record"; selected: root.dashboardTab === "record"; onClicked: root.dashboardTab = "record" }
          DashboardTabButton { label: "Library"; selected: root.dashboardTab === "library"; onClicked: root.dashboardTab = "library" }
        }

        Row {
          visible: !popup.narrowDashboard
          width: parent.width
          height: parent.height - y
          spacing: Style.space(14)

          RecordDashboardColumn {
            width: Math.round((parent.width - parent.spacing) * 0.52)
            height: parent.height
            previewTargetActive: !popup.narrowDashboard
          }

          Rectangle {
            width: 1
            height: parent.height
            color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.14)
          }

          LibraryDashboardColumn {
            width: parent.width - Math.round((parent.width - parent.spacing) * 0.52) - parent.spacing - 1
            height: parent.height
          }
        }

        Item {
          visible: popup.narrowDashboard
          width: parent.width
          height: parent.height - y

          RecordDashboardColumn {
            visible: root.dashboardTab === "record"
            anchors.fill: parent
            previewTargetActive: visible
          }

          LibraryDashboardColumn {
            visible: root.dashboardTab === "library"
            anchors.fill: parent
          }
        }
      }
    }
  }

  component RecordDashboardColumn: Column {
    id: recordColumn
    property bool previewTargetActive: false
    spacing: Style.space(10)

    Text {
      width: parent.width
      text: "RECORD"
      color: root.contentForeground
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }

    SelectorRow {
      width: parent.width
      label: "Folder"
      value: omaloomSettings.outputDirectory
      enabled: root.canStart
      onActivated: root.openFolderPicker()
    }

    ToggleRow {
      width: parent.width
      label: "Current monitor / fullscreen"
      checked: omaloomSettings.recordFullscreen
      enabled: root.canStart
      onToggled: function(checked) { omaloomSettings.recordFullscreen = checked }
    }

    ToggleRow {
      width: parent.width
      label: "System audio"
      checked: omaloomSettings.recordSystemAudio
      enabled: root.canStart
      onToggled: function(checked) { omaloomSettings.recordSystemAudio = checked }
    }

    ToggleRow {
      width: parent.width
      label: "Microphone"
      checked: omaloomSettings.recordMicrophone
      enabled: root.canStart
      onToggled: function(checked) { omaloomSettings.recordMicrophone = checked }
    }

    SelectorRow {
      visible: omaloomSettings.recordMicrophone
      height: visible ? implicitHeight : 0
      width: parent.width
      label: "Mic input"
      value: root.microphoneDevices.length === 0 ? "No microphones found" : root.deviceLabel(root.microphoneDevices, omaloomSettings.microphoneDevice || "default_input", "Default microphone")
      enabled: root.canStart && root.microphoneDevices.length > 0
      onActivated: root.microphoneListOpen = !root.microphoneListOpen
    }

    Repeater {
      model: omaloomSettings.recordMicrophone && root.microphoneListOpen ? root.microphoneDevices : []
      DeviceChoiceRow {
        width: recordColumn.width
        label: modelData.label || modelData.id
        selected: (omaloomSettings.microphoneDevice || "default_input") === modelData.id
        enabled: root.canStart
        onActivated: {
          omaloomSettings.microphoneDevice = modelData.id
          root.microphoneListOpen = false
        }
      }
    }

    ToggleRow {
      width: parent.width
      label: "Webcam overlay"
      checked: omaloomSettings.recordWebcam
      enabled: root.canStart
      onToggled: function(checked) { omaloomSettings.recordWebcam = checked }
    }

    SelectorRow {
      visible: omaloomSettings.recordWebcam
      height: visible ? implicitHeight : 0
      width: parent.width
      label: "Camera"
      value: root.webcamDevices.length === 0 ? "No cameras found" : root.deviceLabel(root.webcamDevices, omaloomSettings.webcamDevice, "Default camera")
      enabled: root.canStart && root.webcamDevices.length > 0
      onActivated: root.webcamListOpen = !root.webcamListOpen
    }

    Repeater {
      model: omaloomSettings.recordWebcam && root.webcamListOpen ? root.webcamDevices : []
      DeviceChoiceRow {
        width: recordColumn.width
        label: modelData.label || modelData.id
        selected: omaloomSettings.webcamDevice === modelData.id
        enabled: root.canStart
        onActivated: {
          omaloomSettings.webcamDevice = modelData.id
          root.webcamListOpen = false
        }
      }
    }

    SelectorRow {
      visible: omaloomSettings.recordWebcam
      height: visible ? implicitHeight : 0
      width: parent.width
      label: "Position"
      value: root.optionLabel(omaloomSettings.webcamPosition)
      enabled: root.canStart
      onActivated: root.cycleWebcamPosition()
    }

    SelectorRow {
      visible: omaloomSettings.recordWebcam
      height: visible ? implicitHeight : 0
      width: parent.width
      label: "Size"
      value: root.optionLabel(omaloomSettings.webcamSize)
      enabled: root.canStart
      onActivated: root.cycleWebcamSize()
    }

    Item {
      visible: omaloomSettings.recordMicrophone || omaloomSettings.recordWebcam
      width: parent.width
      height: visible ? Style.space(20) : 0

      Rectangle { anchors.left: parent.left; anchors.right: previewLabel.left; anchors.rightMargin: Style.space(8); anchors.verticalCenter: parent.verticalCenter; height: 1; color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.22) }
      Text { id: previewLabel; anchors.horizontalCenter: parent.horizontalCenter; anchors.verticalCenter: parent.verticalCenter; text: "REPRESENTATIVE PREVIEW"; color: Qt.darker(root.contentForeground, 1.45); font.family: root.contentFontFamily; font.pixelSize: Style.font.caption; font.bold: true }
      Rectangle { anchors.left: previewLabel.right; anchors.leftMargin: Style.space(8); anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; height: 1; color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.22) }
    }

    Rectangle {
      id: compositionCanvas
      visible: omaloomSettings.recordWebcam
      width: parent.width
      height: visible ? Math.min(Style.space(170), width / root.compositionAspect()) : 0
      radius: Style.cornerRadius
      color: Qt.rgba(0, 0, 0, 0.28)
      border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.18)
      clip: true

      readonly property real tileH: height * root.webcamPreviewScale()
      readonly property real tileW: tileH * 8 / 9
      readonly property real inset: Style.space(10)

      Rectangle {
        anchors.fill: parent
        anchors.margins: Style.space(1)
        radius: Math.max(0, compositionCanvas.radius - Style.space(1))
        color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.035)
      }

      Text {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(10)
        anchors.top: parent.top
        anchors.topMargin: Style.space(8)
        text: "Current monitor composition"
        color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.72)
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
      }

      Rectangle {
        id: compositionTile
        width: compositionCanvas.tileW
        height: compositionCanvas.tileH
        x: omaloomSettings.webcamPosition.indexOf("left") !== -1 ? compositionCanvas.inset : compositionCanvas.width - width - compositionCanvas.inset
        y: omaloomSettings.webcamPosition.indexOf("top") !== -1 ? compositionCanvas.inset : compositionCanvas.height - height - compositionCanvas.inset
        radius: Style.cornerRadius
        color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)
        border.color: Color.accent
        clip: true

        VideoOutput {
          id: previewOutput
          anchors.fill: parent
          visible: root.previewActive && recordColumn.previewTargetActive
          fillMode: VideoOutput.PreserveAspectCrop
          Component.onCompleted: if (recordColumn.previewTargetActive) root.previewOutputTarget = previewOutput
          Component.onDestruction: if (root.previewOutputTarget === previewOutput) root.previewOutputTarget = null
        }

        Connections {
          target: recordColumn
          function onPreviewTargetActiveChanged() {
            if (recordColumn.previewTargetActive) root.previewOutputTarget = previewOutput
            else if (root.previewOutputTarget === previewOutput) root.previewOutputTarget = null
          }
        }

        Text { anchors.centerIn: parent; width: parent.width - Style.space(8); text: root.webcamDevices.length === 0 ? "No camera" : "Camera"; visible: !root.previewActive; color: Qt.darker(root.contentForeground, 1.45); font.family: root.contentFontFamily; font.pixelSize: Style.font.caption; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap }
      }
    }

    Loader {
      id: micMeterLoader
      visible: omaloomSettings.recordMicrophone
      width: parent.width
      height: visible ? Style.space(44) : 0
      active: root.setupResourcesActive && omaloomSettings.recordMicrophone
      sourceComponent: Component { MicMeter { width: micMeterLoader.width; height: micMeterLoader.height; active: true; level: root.microphoneLevel } }
    }

    Item { width: parent.width; height: Style.space(4) }

    Text {
      width: parent.width
      text: root.lastMessage
      color: Qt.darker(root.contentForeground, 1.6)
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.Wrap
      elide: Text.ElideRight
      maximumLineCount: 2
    }

    ActionButton {
      width: parent.width
      height: Style.space(38)
      label: root.state === "error" || root.state === "saved" ? "Start again" : "Start recording"
      enabled: root.canStart
      onClicked: root.startRecording()
    }
  }

  component LibraryDashboardColumn: Column {
    id: libraryColumn
    readonly property real contentRightInset: Style.space(8)
    spacing: Style.space(8)

    Row {
      width: parent.width - libraryColumn.contentRightInset
      height: libraryTitle.implicitHeight
      spacing: Style.space(8)

      Text {
        id: libraryTitle
        width: parent.width - countText.width - parent.spacing
        text: "LIBRARY"
        color: root.contentForeground
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }

      Text {
        id: countText
        text: root.recordingsLoading ? "…" : (root.recordings.length + " MP4" + (root.recordings.length === 1 ? "" : "s"))
        color: Qt.darker(root.contentForeground, 1.45)
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Text {
      visible: !root.busy && (root.recordingsLoading || root.recordingsError !== "" || root.actionFeedback !== "")
      width: parent.width - libraryColumn.contentRightInset
      text: root.recordingsLoading ? "Loading recordings…" : (root.actionFeedback !== "" ? root.actionFeedback : root.recordingsError)
      color: (root.actionFeedback !== "" ? root.actionFeedbackError : root.recordingsError !== "") ? Color.urgent : Qt.darker(root.contentForeground, 1.45)
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.Wrap
      maximumLineCount: 2
    }

    Rectangle {
      visible: !root.busy && root.recordings.length === 0 && !root.recordingsLoading && root.recordingsError === ""
      height: visible ? Style.space(72) : 0
      width: parent.width - libraryColumn.contentRightInset
      radius: Style.cornerRadius
      color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.04)
      border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

      Text {
        anchors.centerIn: parent
        width: parent.width - Style.space(24)
        text: "No MP4 recordings found in the selected folder."
        color: Qt.darker(root.contentForeground, 1.45)
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.bodySmall
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
      }
    }

    ListView {
      id: recordingList
      visible: !root.busy && root.recordings.length > 0
      height: visible ? Math.max(Style.space(120), libraryColumn.height - y) : 0
      width: parent.width - libraryColumn.contentRightInset
      clip: true
      interactive: contentHeight > height
      boundsBehavior: Flickable.StopAtBounds
      spacing: Style.space(4)
      model: visible ? root.recordings : []
      delegate: RecordingLibraryRow {
        width: recordingList.width
        item: modelData
        enabled: !recordingActionProcess.running && !root.recordingsLoading
      }
    }
  }

  component DashboardTabButton: Rectangle {
    id: tabRoot
    property string label: ""
    property bool selected: false
    signal clicked()

    width: (parent.width - parent.spacing) / 2
    height: Style.space(34)
    radius: Style.cornerRadius
    color: selected ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.22) : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.06)
    border.color: selected ? Color.accent : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.18)

    Text {
      anchors.centerIn: parent
      text: tabRoot.label
      color: root.contentForeground
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: tabRoot.selected
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: tabRoot.clicked()
    }
  }

  component MiniActionButton: Rectangle {
    id: miniRoot
    property string label: ""
    signal clicked()

    width: labelText.implicitWidth + Style.space(16)
    height: Style.space(24)
    radius: Style.cornerRadius
    color: enabled ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08) : "transparent"
    border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, enabled ? 0.28 : 0.12)
    opacity: enabled ? 1 : 0.55

    Text {
      id: labelText
      anchors.centerIn: parent
      text: miniRoot.label
      color: root.contentForeground
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.caption
    }

    MouseArea {
      anchors.fill: parent
      enabled: miniRoot.enabled
      cursorShape: Qt.PointingHandCursor
      onClicked: miniRoot.clicked()
    }
  }

  component RecordingLibraryRow: Rectangle {
    id: rowRoot
    property var item: null

    height: Style.space(48)
    radius: Style.cornerRadius
    color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.045)
    border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.11)

    Text {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.right: actionRow.left
      anchors.rightMargin: Style.space(8)
      anchors.top: parent.top
      anchors.topMargin: Style.space(5)
      text: rowRoot.item ? rowRoot.item.name : ""
      color: rowRoot.enabled ? root.contentForeground : Qt.darker(root.contentForeground, 1.8)
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideMiddle
    }

    Text {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.right: actionRow.left
      anchors.rightMargin: Style.space(8)
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(5)
      text: root.recordingMeta(rowRoot.item)
      color: Qt.darker(root.contentForeground, 1.55)
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }

    Row {
      id: actionRow
      anchors.right: parent.right
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)
      MiniActionButton { label: "Open"; enabled: rowRoot.enabled; onClicked: root.runRecordingAction("open", rowRoot.item.path) }
      MiniActionButton { label: "Reveal"; enabled: rowRoot.enabled; onClicked: root.runRecordingAction("reveal", rowRoot.item.path) }
      MiniActionButton { label: "Copy"; enabled: rowRoot.enabled; onClicked: root.runRecordingAction("copy-path", rowRoot.item.path) }
    }

    MouseArea {
      anchors.left: parent.left
      anchors.right: actionRow.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      enabled: rowRoot.enabled
      cursorShape: Qt.PointingHandCursor
      onClicked: root.runRecordingAction("open", rowRoot.item.path)
    }
  }

  component SelectorRow: Item {
    id: selectorRoot
    property string label: ""
    property string value: ""
    signal activated()

    implicitHeight: Style.space(34)

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: selectorRoot.enabled ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.06) : "transparent"
      border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, selectorRoot.enabled ? 0.22 : 0.12)

      Row {
        anchors.fill: parent
        anchors.leftMargin: Style.space(8)
        anchors.rightMargin: Style.space(8)
        spacing: Style.space(8)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(78)
          text: selectorRoot.label
          color: selectorRoot.enabled ? root.contentForeground : Qt.darker(root.contentForeground, 1.8)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - Style.space(108)
          text: selectorRoot.value
          color: Qt.darker(root.contentForeground, selectorRoot.enabled ? 1.25 : 1.8)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideMiddle
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "›"
          color: selectorRoot.enabled ? root.contentForeground : Qt.darker(root.contentForeground, 1.8)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      enabled: selectorRoot.enabled
      cursorShape: Qt.PointingHandCursor
      onClicked: selectorRoot.activated()
    }
  }

  component DeviceChoiceRow: Item {
    id: choiceRoot
    property string label: ""
    property bool selected: false
    signal activated()

    implicitHeight: Style.space(26)

    Text {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(22)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: (choiceRoot.selected ? "✓ " : "  ") + choiceRoot.label
      color: choiceRoot.enabled ? root.contentForeground : Qt.darker(root.contentForeground, 1.8)
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideMiddle
    }

    MouseArea {
      anchors.fill: parent
      enabled: choiceRoot.enabled
      cursorShape: Qt.PointingHandCursor
      onClicked: choiceRoot.activated()
    }
  }

  component MicMeter: Item {
    id: meterRoot
    property bool active: false
    property real level: 0
    property real phase: 0

    implicitHeight: Style.space(44)

    NumberAnimation on phase {
      from: 0
      to: Math.PI * 2
      duration: 900
      loops: Animation.Infinite
      running: meterRoot.active
    }

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.06)
      border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.16)

      Row {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(10)
        anchors.right: micLiveLabel.left
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height - Style.space(14)
        spacing: Style.space(3)

        Repeater {
          model: 14
          Rectangle {
            readonly property real pulse: 0.3 + 0.7 * Math.abs(Math.sin(meterRoot.phase + index * 0.72))
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(4)
            height: Math.max(Style.space(3), parent.height * Math.max(0.08, meterRoot.level) * pulse)
            radius: width / 2
            color: Color.accent
            opacity: 0.35 + 0.65 * Math.max(0.08, meterRoot.level)
          }
        }
      }

      Text {
        id: micLiveLabel
        anchors.right: parent.right
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        text: "Mic live"
        color: Qt.darker(root.contentForeground, 1.35)
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  component ToggleRow: Item {
    id: toggleRoot
    property string label: ""
    property bool checked: false
    signal toggled(bool checked)

    implicitHeight: Style.space(24)

    Row {
      anchors.fill: parent
      spacing: Style.space(8)

      Rectangle {
        width: Style.space(16)
        height: Style.space(16)
        anchors.verticalCenter: parent.verticalCenter
        radius: Style.cornerRadius > 0 ? Style.space(3) : 0
        color: toggleRoot.checked ? Color.accent : "transparent"
        border.color: toggleRoot.enabled ? root.contentForeground : Qt.darker(root.contentForeground, 1.8)

        Text {
          anchors.centerIn: parent
          text: toggleRoot.checked ? "✓" : ""
          color: Color.background
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: toggleRoot.label
        color: toggleRoot.enabled ? root.contentForeground : Qt.darker(root.contentForeground, 1.8)
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    MouseArea {
      anchors.fill: parent
      enabled: toggleRoot.enabled
      cursorShape: Qt.PointingHandCursor
      onClicked: toggleRoot.toggled(!toggleRoot.checked)
    }
  }

  component ActionButton: Rectangle {
    id: actionRoot
    property string label: ""
    signal clicked()

    width: Style.space(116)
    height: Style.space(34)
    radius: Style.cornerRadius
    color: enabled ? Style.hoverFillFor(root.contentForeground, Color.accent) : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)
    border.color: enabled ? root.contentForeground : Qt.darker(root.contentForeground, 1.8)
    opacity: enabled ? 1 : 0.55

    Text {
      anchors.centerIn: parent
      text: actionRoot.label
      color: root.contentForeground
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }

    MouseArea {
      anchors.fill: parent
      enabled: actionRoot.enabled
      cursorShape: Qt.PointingHandCursor
      onClicked: actionRoot.clicked()
    }
  }
}
