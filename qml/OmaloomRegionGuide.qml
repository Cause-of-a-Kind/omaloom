import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

Item {
  id: root

  property bool active: false
  property var guide: null
  property color accent: Color.accent
  property real thickness: 2
  property real shadeOpacity: 0.12

  function monitorFor(screenName) {
    if (!guide || !Array.isArray(guide.monitors)) return null
    for (var i = 0; i < guide.monitors.length; i++) {
      if (String(guide.monitors[i].name) === String(screenName)) return guide.monitors[i]
    }
    return null
  }

  function localRectFor(screenName, screenWidth, screenHeight) {
    if (!guide || guide.type !== "region" || !guide.region) return { visible: false }
    var monitor = monitorFor(screenName)
    if (!monitor) return { visible: false }

    var region = guide.region
    var left = Math.max(region.x, monitor.x)
    var top = Math.max(region.y, monitor.y)
    var right = Math.min(region.x + region.width, monitor.x + monitor.width)
    var bottom = Math.min(region.y + region.height, monitor.y + monitor.height)
    if (right <= left || bottom <= top) return { visible: false }

    // Hyprland/slurp geometry is logical. PanelWindow coordinates are screen
    // local. If a compositor/backend reports different logical dimensions for
    // QScreen, scale into that local coordinate space instead of assuming 1:1.
    var sx = monitor.width > 0 ? screenWidth / monitor.width : 1
    var sy = monitor.height > 0 ? screenHeight / monitor.height : 1
    var lx = Math.floor((left - monitor.x) * sx)
    var ly = Math.floor((top - monitor.y) * sy)
    var lr = Math.ceil((right - monitor.x) * sx)
    var lb = Math.ceil((bottom - monitor.y) * sy)
    return {
      visible: true,
      x: lx,
      y: ly,
      width: Math.max(0, lr - lx),
      height: Math.max(0, lb - ly)
    }
  }

  Variants {
    model: root.active && root.guide && root.guide.type === "region" ? Quickshell.screens : []

    delegate: PanelWindow {
      id: win

      required property var modelData
      readonly property var localRegion: root.localRectFor(modelData.name, width, height)
      readonly property int t: Math.max(1, Math.round(root.thickness))
      readonly property bool hasRegion: localRegion.visible === true
      readonly property int rx: hasRegion ? localRegion.x : 0
      readonly property int ry: hasRegion ? localRegion.y : 0
      readonly property int rw: hasRegion ? localRegion.width : 0
      readonly property int rh: hasRegion ? localRegion.height : 0

      screen: modelData
      visible: root.active && hasRegion
      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      mask: Region {}

      WlrLayershell.namespace: "coak-omaloom-region-guide"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      // Subtle outside-only shading. No pixels are drawn inside the selected
      // region, so the guide cannot be captured by gpu-screen-recorder's region
      // grab even when the layer is visible.
      Rectangle { x: 0; y: 0; width: win.width; height: win.ry; color: Qt.rgba(0, 0, 0, root.shadeOpacity); visible: win.hasRegion && win.ry > 0 }
      Rectangle { x: 0; y: win.ry + win.rh; width: win.width; height: Math.max(0, win.height - (win.ry + win.rh)); color: Qt.rgba(0, 0, 0, root.shadeOpacity); visible: win.hasRegion && y < win.height }
      Rectangle { x: 0; y: win.ry; width: win.rx; height: win.rh; color: Qt.rgba(0, 0, 0, root.shadeOpacity); visible: win.hasRegion && win.rx > 0 }
      Rectangle { x: win.rx + win.rw; y: win.ry; width: Math.max(0, win.width - (win.rx + win.rw)); height: win.rh; color: Qt.rgba(0, 0, 0, root.shadeOpacity); visible: win.hasRegion && x < win.width }

      // Outside-only outline. Sides at monitor edges are omitted instead of
      // being drawn inward into the captured region.
      Rectangle { x: win.rx; y: win.ry - win.t; width: win.rw; height: win.t; color: root.accent; visible: win.hasRegion && win.ry >= win.t }
      Rectangle { x: win.rx; y: win.ry + win.rh; width: win.rw; height: win.t; color: root.accent; visible: win.hasRegion && y + height <= win.height }
      Rectangle { x: win.rx - win.t; y: win.ry; width: win.t; height: win.rh; color: root.accent; visible: win.hasRegion && win.rx >= win.t }
      Rectangle { x: win.rx + win.rw; y: win.ry; width: win.t; height: win.rh; color: root.accent; visible: win.hasRegion && x + width <= win.width }
    }
  }
}
