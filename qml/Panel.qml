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

  property var shell: null
  property var manifest: null
  property var anchorItem: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string installedRecorder: home + "/.config/omarchy/plugins/coak.omaloom/bin/omaloom-recorder"
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  property string state: "idle"
  property string lastMessage: "Ready to record locally."

  function open(payloadJson) {
    root.controller.show()
    statusProcess.command = [recorderCommand(), "status"]
    statusProcess.running = true
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (opened) close()
    else open("")
  }

  function recorderCommand() {
    return installedRecorder
  }

  function startRecording() {
    var args = [recorderCommand(), "start", "--directory", omaloomSettings.outputDirectory]
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
    state = omaloomSettings.recordFullscreen ? "recording" : "selecting"
    actionProcess.command = args
    actionProcess.running = true
  }

  function stopRecording() {
    state = "stopping"
    actionProcess.command = [recorderCommand(), "stop"]
    actionProcess.running = true
  }

  function updateFromLine(line) {
    var text = String(line || "")
    lastMessage = text
    if (text.indexOf('"recording_started"') !== -1) state = "recording"
    else if (text.indexOf('"saved"') !== -1) state = "saved"
    else if (text.indexOf('"state":"recording"') !== -1) state = "recording"
    else if (text.indexOf('"state":"idle"') !== -1) state = "idle"
    else if (text.indexOf('"error"') !== -1) state = "error"
  }

  OmaloomSettings { id: omaloomSettings }

  Process {
    id: statusProcess
    stdout: SplitParser { onRead: function(line) { root.updateFromLine(line) } }
  }

  Process {
    id: actionProcess
    stdout: SplitParser { onRead: function(line) { root.updateFromLine(line) } }
    stderr: SplitParser { onRead: function(line) { root.lastMessage = String(line); root.state = "error" } }
  }

  KeyboardPanel {
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened
    centerOnBar: true
    contentWidth: Style.space(380)
    contentHeight: Style.space(230)

    Rectangle {
      anchors.fill: parent
      color: Color.background
      radius: Style.cornerRadius
      border.color: root.state === "recording" ? Color.urgent : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.25)

      Column {
        anchors.fill: parent
        anchors.margins: Style.space(16)
        spacing: Style.space(10)

        Text {
          textFormat: Text.PlainText
          text: "Omaloom"
          color: root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Text {
          textFormat: Text.PlainText
          text: "State: " + root.state
          color: root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: "Folder: " + omaloomSettings.outputDirectory
          color: Qt.darker(root.contentForeground, 1.35)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: root.lastMessage
          color: Qt.darker(root.contentForeground, 1.6)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
          elide: Text.ElideRight
          maximumLineCount: 2
        }

        Row {
          spacing: Style.space(10)

          PanelActionButton {
            iconText: "●"
            tooltipText: "Start recording"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            onClicked: root.startRecording()
          }

          PanelActionButton {
            iconText: "■"
            tooltipText: "Stop recording"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            onClicked: root.stopRecording()
          }
        }
      }
    }
  }
}
