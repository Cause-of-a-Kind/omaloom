import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string moduleName: "coak.omaloom"
  readonly property string home: Quickshell.env("HOME")
  readonly property string installedRecorder: home + "/.config/omarchy/plugins/coak.omaloom/bin/omaloom-recorder"

  property string state: "idle"
  property string lastSavedPath: ""
  property string lastError: ""

  function setState(nextState) {
    state = nextState
    console.log("omaloom state " + nextState)
  }

  function recorderCommand() {
    return installedRecorder
  }

  function refreshStatus() {
    statusProcess.command = [recorderCommand(), "status"]
    statusProcess.running = true
  }

  function startRecording() {
    if (state === "recording" || state === "selecting" || startProcess.running) return
    lastError = ""
    setState(omaloomSettings.recordFullscreen ? "recording" : "selecting")
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

    startProcess.command = args
    startProcess.running = true
  }

  function stopRecording() {
    if (stopProcess.running) return
    setState("stopping")
    stopProcess.running = true
  }

  function handleLine(line) {
    var text = String(line || "")
    if (text.indexOf('"recording_started"') !== -1) setState("recording")
    else if (text.indexOf('"saved"') !== -1) {
      var match = text.match(/"path":"([^"]*)"/)
      lastSavedPath = match ? match[1] : ""
      setState("saved")
    } else if (text.indexOf('"state":"recording"') !== -1) setState("recording")
    else if (text.indexOf('"state":"idle"') !== -1 && state !== "saved") setState("idle")
    else if (text.indexOf('"error"') !== -1) {
      lastError = text
      setState("error")
    }
  }

  OmaloomSettings { id: omaloomSettings }

  Component.onCompleted: refreshStatus()

  Process {
    id: statusProcess
    command: [root.recorderCommand(), "status"]
    stdout: SplitParser { onRead: function(line) { root.handleLine(line) } }
  }

  Process {
    id: startProcess
    stdout: SplitParser { onRead: function(line) { root.handleLine(line) } }
    stderr: SplitParser { onRead: function(line) { root.lastError = String(line); root.setState("error") } }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.state !== "error") {
        root.lastError = "recorder start exited " + exitCode
        root.setState("error")
      }
    }
  }

  Process {
    id: stopProcess
    command: [root.recorderCommand(), "stop"]
    stdout: SplitParser { onRead: function(line) { root.handleLine(line) } }
    stderr: SplitParser { onRead: function(line) { root.lastError = String(line); root.setState("error") } }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.state !== "error") {
        root.lastError = "recorder stop exited " + exitCode
        root.setState("error")
      }
    }
  }
}
