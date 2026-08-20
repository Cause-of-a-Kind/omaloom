import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string defaultDirectory: home + "/Videos/Omaloom"
  readonly property string settingsPath: home + "/.config/omaloom/settings.json"
  readonly property string installedSettingsHelper: home + "/.config/omarchy/plugins/coak.omaloom/bin/omaloom-settings"

  property string outputDirectory: defaultDirectory
  property bool recordFullscreen: false
  property bool recordSystemAudio: true
  property bool recordMicrophone: true
  property bool recordWebcam: false
  property string microphoneDevice: ""
  property string webcamDevice: ""

  property bool initialized: false
  property bool applying: false
  property var pendingSaves: ({})
  property string activeSaveKey: ""

  function boolValue(value, fallback) {
    return typeof value === "boolean" ? value : fallback
  }

  function stringValue(value, fallback) {
    return typeof value === "string" && value.length > 0 ? value : fallback
  }

  function applyObject(obj) {
    applying = true
    outputDirectory = stringValue(obj ? obj.outputDirectory : undefined, defaultDirectory)
    recordFullscreen = boolValue(obj ? obj.fullscreenCurrentMonitor : undefined, false)
    recordSystemAudio = boolValue(obj ? obj.systemAudio : undefined, true)
    recordMicrophone = boolValue(obj ? obj.microphone : undefined, true)
    recordWebcam = boolValue(obj ? obj.webcam : undefined, false)
    microphoneDevice = stringValue(obj ? obj.microphoneDevice : undefined, "")
    webcamDevice = stringValue(obj ? obj.webcamDevice : undefined, "")
    applying = false
    initialized = true
  }

  function applyText(text) {
    try {
      applyObject(JSON.parse(String(text || "{}")))
    } catch (e) {
      console.warn("Omaloom settings parse failed; using defaults:", e)
      applyObject({})
    }
  }

  function saveValue(key, value) {
    if (!initialized || applying) return
    var next = ({})
    for (var k in pendingSaves) next[k] = pendingSaves[k]
    next[key] = value
    pendingSaves = next
    flushSaves()
  }

  function flushSaves() {
    if (saveProcess.running) return
    var keys = Object.keys(pendingSaves)
    if (keys.length === 0) return
    var key = keys[0]
    var next = ({})
    for (var k in pendingSaves) if (k !== key) next[k] = pendingSaves[k]
    activeSaveKey = key
    saveProcess.command = [installedSettingsHelper, "set", key, String(pendingSaves[key])]
    pendingSaves = next
    saveProcess.running = true
  }

  onOutputDirectoryChanged: saveValue("outputDirectory", outputDirectory)
  onRecordFullscreenChanged: saveValue("fullscreenCurrentMonitor", recordFullscreen ? "true" : "false")
  onRecordSystemAudioChanged: saveValue("systemAudio", recordSystemAudio ? "true" : "false")
  onRecordMicrophoneChanged: saveValue("microphone", recordMicrophone ? "true" : "false")
  onRecordWebcamChanged: saveValue("webcam", recordWebcam ? "true" : "false")
  onMicrophoneDeviceChanged: saveValue("microphoneDevice", microphoneDevice)
  onWebcamDeviceChanged: saveValue("webcamDevice", webcamDevice)

  FileView {
    id: settingsFile
    path: root.settingsPath
    watchChanges: true
    printErrors: false
    onLoaded: root.applyText(text())
    onLoadFailed: root.applyObject({})
    onFileChanged: reload()
  }

  Process {
    id: saveProcess
    stdout: SplitParser { onRead: function(line) { root.applyText(line) } }
    stderr: SplitParser { onRead: function(line) { console.warn("Omaloom settings save failed:", String(line)) } }
    onExited: function(exitCode) {
      if (exitCode !== 0) console.warn("Omaloom settings save exited", exitCode, "for", root.activeSaveKey)
      root.activeSaveKey = ""
      root.flushSaves()
    }
  }
}
