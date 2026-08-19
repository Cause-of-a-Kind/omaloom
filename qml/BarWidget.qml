import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "coak.omaloom"
  ipcTarget: "coak.omaloom"
  manageIpc: false

  readonly property string home: Quickshell.env("HOME")
  readonly property string recorder: home + "/.config/omarchy/plugins/coak.omaloom/bin/omaloom-recorder"
  // Elm-ish model: state is owned by backend observations. The backend owns
  // source selection, then countdown, then gpu-screen-recorder startup.
  readonly property bool selecting: state === "selecting"
  readonly property bool countdown: state === "countdown"
  readonly property bool starting: state === "starting"
  readonly property bool recording: state === "recording"
  readonly property bool busy: selecting || countdown || starting || recording
  readonly property bool canStart: !startDelay.running && !actionProcess.running && !busy
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  property bool interactive: true
  property bool pressable: true
  property bool concealed: false
  property string state: "idle"
  property string outputDirectory: home + "/Videos/Omaloom"
  property string lastMessage: "Ready to record locally."
  property string lastSavedPath: ""
  property bool clickStatusSawRecording: false
  property int countdownRemaining: 5
  property var pendingStartArgs: []
  property bool recordFullscreen: false
  property bool recordMicrophone: true
  property bool recordSystemAudio: true
  property bool recordWebcam: false

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
    var args = [recorder, "start", "--directory", outputDirectory]
    if (recordFullscreen) args.push("--fullscreen")
    if (recordSystemAudio) args.push("--desktop-audio")
    if (recordMicrophone) args.push("--microphone")
    if (recordWebcam) args.push("--webcam")
    lastMessage = recordFullscreen ? "Preparing current-monitor recording…" : "Preparing source selector…"
    lastSavedPath = ""
    pendingStartArgs = args
    countdownRemaining = 5
    state = recordFullscreen ? "starting" : "selecting"

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

  function extractJsonString(text, key) {
    var re = new RegExp('"' + key + '":"([^"]*)"')
    var match = String(text || "").match(re)
    if (!match) return ""
    return match[1].replace(/\\n/g, "\n").replace(/\\t/g, "\t").replace(/\\r/g, "\r").replace(/\\"/g, '"').replace(/\\\\/g, "\\")
  }

  function updateFromLine(line) {
    var text = String(line || "")
    if (text === "") return
    lastMessage = text

    if (text.indexOf('"source_selected"') !== -1) {
      state = "countdown"
      countdownRemaining = 5
      lastMessage = "Source selected. Recording starts after countdown…"
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
      lastMessage = "Selection cancelled. Ready to record locally."
    } else if (text.indexOf('"saved"') !== -1) {
      lastSavedPath = extractJsonString(text, "path")
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
        state = "idle"
        lastMessage = "Recording stopped. Ready to record locally."
      } else if (state !== "saved") {
        state = "idle"
        lastMessage = lastSavedPath ? "Last saved: " + lastSavedPath : "Ready to record locally."
      }
    } else if (text.indexOf('"error"') !== -1) {
      state = "error"
      var message = extractJsonString(text, "message")
      lastMessage = message || text
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()

  Timer {
    interval: root.busy ? 1000 : 3000
    repeat: true
    running: true
    onTriggered: root.refresh()
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
        root.state = "idle"
        root.lastMessage = "Recording was not started. Ready to record locally."
        root.refresh()
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
    stderr: SplitParser { onRead: function(line) { root.lastMessage = String(line); root.state = "error" } }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.state !== "error" && root.state !== "idle") {
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
    contentWidth: popup.fittedContentWidth(Style.space(420))
    contentHeight: popup.fittedContentHeight(panelColumn.implicitHeight, Style.space(420))

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
        height: visible ? implicitHeight : 0
        text: String(root.countdownRemaining)
        color: Color.accent
        font.family: root.contentFontFamily
        font.pixelSize: Style.space(96)
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
      }

      Text {
        visible: !root.countdown
        height: visible ? implicitHeight : 0
        width: parent.width
        text: "Folder: " + root.outputDirectory
        color: Qt.darker(root.contentForeground, 1.35)
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.Wrap
      }

      ToggleRow {
        visible: !root.countdown
        height: visible ? implicitHeight : 0
        width: parent.width
        label: "Current monitor / fullscreen"
        checked: root.recordFullscreen
        enabled: root.canStart
        onToggled: root.recordFullscreen = checked
      }

      ToggleRow {
        visible: !root.countdown
        height: visible ? implicitHeight : 0
        width: parent.width
        label: "System audio"
        checked: root.recordSystemAudio
        enabled: root.canStart
        onToggled: root.recordSystemAudio = checked
      }

      ToggleRow {
        visible: !root.countdown
        height: visible ? implicitHeight : 0
        width: parent.width
        label: "Microphone"
        checked: root.recordMicrophone
        enabled: root.canStart
        onToggled: root.recordMicrophone = checked
      }

      ToggleRow {
        visible: !root.countdown
        height: visible ? implicitHeight : 0
        width: parent.width
        label: "Webcam overlay"
        checked: root.recordWebcam
        enabled: root.canStart
        onToggled: root.recordWebcam = checked
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
        height: visible ? Style.space(34) : 0
        label: root.state === "error" || root.state === "saved" ? "Start again" : "Start recording"
        enabled: root.canStart
        onClicked: root.startRecording()
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
