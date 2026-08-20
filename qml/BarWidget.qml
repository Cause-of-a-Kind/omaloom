import QtQuick
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
  // Elm-ish model: state is owned by backend observations. The backend owns
  // source selection, then countdown, then gpu-screen-recorder startup.
  readonly property bool selecting: state === "selecting"
  readonly property bool countdown: state === "countdown"
  readonly property bool starting: state === "starting"
  readonly property bool recording: state === "recording"
  readonly property bool busy: selecting || countdown || starting || recording
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
    }
    lastMessage = omaloomSettings.recordFullscreen ? "Preparing current-monitor recording…" : "Preparing source selector…"
    lastSavedPath = ""
    hideRegionGuide()
    pendingStartArgs = args
    countdownRemaining = 5
    state = omaloomSettings.recordFullscreen ? "starting" : "selecting"
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
      state = "starting"
      countdownRemaining = 5
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
      maybeShowRegionGuide(event)
    } else if (text.indexOf('"cancelled"') !== -1) {
      state = "idle"
      hideRegionGuide()
      lastMessage = "Selection cancelled. Ready to record locally."
    } else if (text.indexOf('"saved"') !== -1) {
      lastSavedPath = extractJsonString(text, "path")
      hideRegionGuide()
      state = "saved"
      lastMessage = lastSavedPath ? "Saved: " + lastSavedPath : "Recording saved."
    } else if (text.indexOf('"state":"recording"') !== -1) {
      state = "recording"
      var activePath = extractJsonString(text, "path")
      lastMessage = activePath ? "Recording: " + activePath : "Recording…"
    } else if (text.indexOf('"state":"idle"') !== -1) {
      if (state === "selecting" || state === "countdown" || state === "starting") {
        // During source selection/countdown gpu-screen-recorder does not exist
        // yet. Keep the UI in its local state until it becomes recording,
        // cancelled, or the timeout resets.
        return
      }
      if (state === "recording") {
        hideRegionGuide()
        state = "idle"
        lastMessage = "Recording stopped. Ready to record locally."
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
          videoOutput: previewOutput
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
      if (root.state === "selecting" || root.state === "countdown" || root.state === "starting") {
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
    text: root.countdown ? String(root.countdownRemaining) : (root.recording ? "REC" : "Omaloom")
    active: root.recording || root.countdown
    tooltipText: root.recording ? "Recording — use the Omarchy stop button at the top center" : (root.countdown ? "Recording starts in " + root.countdownRemaining : (root.selecting ? "Select a source/region" : (root.starting ? "Starting recording…" : "Open Omaloom")))
    labelVisible: !(root.bar && root.bar.vertical === true)
    hasVisualContent: true
    horizontalMargin: 8.75
    verticalPadding: 8.75

    onPressed: function(mouseButton) { root.triggerPress(mouseButton) }

    Text {
      visible: root.bar && root.bar.vertical === true
      anchors.centerIn: parent
      text: root.countdown ? String(root.countdownRemaining) : (root.recording ? "●" : "◌")
      color: root.recording ? Color.urgent : button.foreground
      font.family: button.fontFamily
      font.pixelSize: button.fontSize
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    centerOnBar: true
    contentWidth: popup.fittedContentWidth(Style.space(460))
    contentHeight: popup.fittedContentHeight(panelColumn.implicitHeight, Style.space(560))

    Column {
      id: panelColumn
      width: parent.width
      spacing: Style.space(10)

      Text {
        text: "Omaloom"
        color: root.contentForeground
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.title
        font.bold: true
      }

      Text {
        text: root.countdown ? "Recording starts in" : (root.recording ? "Recording" : (root.starting ? "Starting…" : "Ready"))
        color: root.contentForeground
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        visible: root.countdown
        width: parent.width
        text: String(root.countdownRemaining)
        color: Color.accent
        font.family: root.contentFontFamily
        font.pixelSize: Style.space(96)
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
      }

      SelectorRow {
        visible: !root.countdown
        height: visible ? implicitHeight : 0
        width: parent.width
        label: "Folder"
        value: omaloomSettings.outputDirectory
        enabled: root.canStart
        onActivated: root.openFolderPicker()
      }

      ToggleRow {
        visible: !root.countdown
        height: visible ? implicitHeight : 0
        width: parent.width
        label: "Current monitor / fullscreen"
        checked: omaloomSettings.recordFullscreen
        enabled: root.canStart
        onToggled: function(checked) { omaloomSettings.recordFullscreen = checked }
      }

      ToggleRow {
        visible: !root.countdown
        height: visible ? implicitHeight : 0
        width: parent.width
        label: "System audio"
        checked: omaloomSettings.recordSystemAudio
        enabled: root.canStart
        onToggled: function(checked) { omaloomSettings.recordSystemAudio = checked }
      }

      ToggleRow {
        visible: !root.countdown
        height: visible ? implicitHeight : 0
        width: parent.width
        label: "Microphone"
        checked: omaloomSettings.recordMicrophone
        enabled: root.canStart
        onToggled: function(checked) { omaloomSettings.recordMicrophone = checked }
      }

      SelectorRow {
        visible: !root.countdown && omaloomSettings.recordMicrophone
        height: visible ? implicitHeight : 0
        width: parent.width
        label: "Mic input"
        value: root.microphoneDevices.length === 0 ? "No microphones found" : root.deviceLabel(root.microphoneDevices, omaloomSettings.microphoneDevice || "default_input", "Default microphone")
        enabled: root.canStart && root.microphoneDevices.length > 0
        onActivated: root.microphoneListOpen = !root.microphoneListOpen
      }

      Repeater {
        model: (!root.countdown && omaloomSettings.recordMicrophone && root.microphoneListOpen) ? root.microphoneDevices : []
        DeviceChoiceRow {
          width: panelColumn.width
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
        visible: !root.countdown
        height: visible ? implicitHeight : 0
        width: parent.width
        label: "Webcam overlay"
        checked: omaloomSettings.recordWebcam
        enabled: root.canStart
        onToggled: function(checked) { omaloomSettings.recordWebcam = checked }
      }

      SelectorRow {
        visible: !root.countdown && omaloomSettings.recordWebcam
        height: visible ? implicitHeight : 0
        width: parent.width
        label: "Camera"
        value: root.webcamDevices.length === 0 ? "No cameras found" : root.deviceLabel(root.webcamDevices, omaloomSettings.webcamDevice, "Default camera")
        enabled: root.canStart && root.webcamDevices.length > 0
        onActivated: root.webcamListOpen = !root.webcamListOpen
      }

      Repeater {
        model: (!root.countdown && omaloomSettings.recordWebcam && root.webcamListOpen) ? root.webcamDevices : []
        DeviceChoiceRow {
          width: panelColumn.width
          label: modelData.label || modelData.id
          selected: omaloomSettings.webcamDevice === modelData.id
          enabled: root.canStart
          onActivated: {
            omaloomSettings.webcamDevice = modelData.id
            root.webcamListOpen = false
          }
        }
      }

      Item {
        visible: !root.countdown && (omaloomSettings.recordMicrophone || omaloomSettings.recordWebcam)
        width: parent.width
        height: visible ? Style.space(22) : 0

        Rectangle {
          anchors.left: parent.left
          anchors.right: previewLabel.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          height: 1
          color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.22)
        }

        Text {
          id: previewLabel
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.verticalCenter: parent.verticalCenter
          text: "LIVE PREVIEW"
          color: Qt.darker(root.contentForeground, 1.45)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Rectangle {
          anchors.left: previewLabel.right
          anchors.leftMargin: Style.space(8)
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          height: 1
          color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.22)
        }
      }

      Row {
        visible: !root.countdown && (omaloomSettings.recordMicrophone || omaloomSettings.recordWebcam)
        height: visible ? Math.max(micMeterLoader.height, webcamPreview.height) : 0
        width: parent.width
        spacing: Style.space(10)

        Loader {
          id: micMeterLoader
          width: parent.width - (webcamPreview.visible ? webcamPreview.width + parent.spacing : 0)
          visible: omaloomSettings.recordMicrophone
          height: visible ? Style.space(44) : 0
          active: root.setupResourcesActive && omaloomSettings.recordMicrophone
          sourceComponent: Component {
            MicMeter {
              width: micMeterLoader.width
              height: micMeterLoader.height
              active: true
              level: root.microphoneLevel
            }
          }
        }

        Rectangle {
          id: webcamPreview
          visible: omaloomSettings.recordWebcam
          width: Style.space(112)
          height: width
          radius: Style.cornerRadius
          color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)
          border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.22)
          clip: true

          VideoOutput {
            id: previewOutput
            anchors.fill: parent
            visible: root.previewActive
            fillMode: VideoOutput.PreserveAspectCrop
          }

          Text {
            anchors.centerIn: parent
            width: parent.width - Style.space(12)
            text: root.webcamDevices.length === 0 ? "No camera" : "Preview"
            visible: !root.previewActive
            color: Qt.darker(root.contentForeground, 1.45)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
          }
        }
      }

      Text {
        visible: !root.countdown
        height: visible ? implicitHeight : 0
        width: parent.width
        text: root.lastMessage + (root.recording ? " Use the Omarchy stop button at the top center to finish." : "")
        color: Qt.darker(root.contentForeground, 1.6)
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.Wrap
        elide: Text.ElideRight
        maximumLineCount: 3
      }

      ActionButton {
        visible: !root.countdown
        width: parent.width
        height: visible ? Style.space(34) : 0
        label: root.state === "error" || root.state === "saved" ? "Start again" : "Start recording"
        enabled: root.canStart
        onClicked: root.startRecording()
      }
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
