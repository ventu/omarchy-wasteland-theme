import QtQuick

// CRT tube-TV beam drawn over the live desktop (Nov 15, 2026).
//   mode "on":  black -> dot -> horizontal line -> picture opens with a short
//               brightness flicker (~590 ms), then finished() and the window hides.
//   mode "off": picture squashes to a bright line -> dot -> black (~500 ms),
//               then holds black; Service.qml's safety timer hides it.
// Plain rectangles + NumberAnimation only: no blur, no shaders. Nothing runs
// once the animation stops, and the window is unmapped afterwards.
Item {
  id: beam

  property string mode: ""
  property int serial: 0
  // hold: keep the "on" animation on black until released (unlock waits for
  // shown(), the first frame this overlay actually draws, then releases it).
  property bool hold: false
  property var held: null
  property bool awaitingShown: false
  signal finished()
  signal shown()

  readonly property color colorBeam: "#e6f2d6"
  readonly property color colorGlow: "#8fbf6a"

  property real openW: 0
  property real openH: 0
  property real glow: 0
  property real dotSize: 0
  property real dotOpacity: 0
  property bool pendingPlay: false

  visible: mode !== ""

  function play() {
    // The layer surface may not have its size yet on the first call.
    // Defaults are all black, so the first frame already counts as shown.
    if (mode === "on") awaitingShown = true
    if (width <= 0 || height <= 0) { pendingPlay = true; return }
    pendingPlay = false
    onAnim.stop()
    offAnim.stop()
    queued = null
    held = null
    if (mode === "on") {
      openW = 0; openH = 0; glow = 1; dotSize = 2; dotOpacity = 0
      awaitingShown = true
      if (hold) {
        held = onAnim
      } else {
        queued = onAnim
        startFallback.restart()
      }
    } else if (mode === "off") {
      openW = width; openH = height; glow = 0; dotSize = 10; dotOpacity = 0
      queued = offAnim
      startFallback.restart()
    }
  }

  // Start on the next frame actually shown (a freshly mapped layer can take a
  // moment), so the animation is not spent off-screen. Fallback after 300 ms.
  property var queued: null
  function kick() {
    if (!queued) return
    var a = queued
    queued = null
    startFallback.stop()
    a.start()
  }
  Connections {
    target: beam.Window.window
    ignoreUnknownSignals: true
    function onFrameSwapped() {
      if (beam.awaitingShown) {
        beam.awaitingShown = false
        beam.shown()
      }
      beam.kick()
    }
  }
  Timer { id: startFallback; interval: 300; onTriggered: beam.kick() }

  // Released (the lock is gone): start right away, not on a later frame.
  onHoldChanged: {
    if (hold || !held) return
    var a = held
    held = null
    a.start()
  }

  onModeChanged: play()
  onSerialChanged: play()
  onWidthChanged: if (pendingPlay) play()
  onHeightChanged: if (pendingPlay) play()

  readonly property real ox: Math.round((width - openW) / 2)
  readonly property real oy: Math.round((height - openH) / 2)

  // Black mask around the open "picture" area.
  Rectangle { color: "black"; x: 0; y: 0; width: beam.width; height: beam.oy }
  Rectangle { color: "black"; x: 0; y: beam.oy + beam.openH; width: beam.width; height: beam.height - y }
  Rectangle { color: "black"; x: 0; y: beam.oy; width: beam.ox; height: beam.openH }
  Rectangle { color: "black"; x: beam.ox + beam.openW; y: beam.oy; width: beam.width - x; height: beam.openH }

  // Phosphor glow over the open area (the bright line, then the flicker).
  Rectangle {
    x: beam.ox; y: beam.oy; width: beam.openW; height: beam.openH
    color: beam.colorBeam
    opacity: beam.glow
    visible: opacity > 0.001 && width > 0 && height > 0
  }
  // A faint green halo just around the line while it is thin.
  Rectangle {
    x: beam.ox; y: beam.oy - 3; width: beam.openW; height: beam.openH + 6
    color: beam.colorGlow
    opacity: beam.openH < 12 ? beam.glow * 0.35 : 0
    visible: opacity > 0.001 && width > 0
  }

  Rectangle {
    width: beam.dotSize; height: beam.dotSize; radius: width / 2
    x: Math.round((beam.width - width) / 2); y: Math.round((beam.height - height) / 2)
    color: beam.colorBeam
    opacity: beam.dotOpacity
    visible: opacity > 0.001
  }

  SequentialAnimation {
    id: onAnim
    ParallelAnimation {
      NumberAnimation { target: beam; property: "dotOpacity"; to: 1; duration: 70 }
      NumberAnimation { target: beam; property: "dotSize"; to: 10; duration: 70; easing.type: Easing.OutQuad }
    }
    ParallelAnimation {
      NumberAnimation { target: beam; property: "openW"; from: 4; to: beam.width; duration: 130; easing.type: Easing.OutCubic }
      NumberAnimation { target: beam; property: "openH"; from: 3; to: 3; duration: 130 }
      NumberAnimation { target: beam; property: "dotOpacity"; to: 0; duration: 90 }
    }
    ParallelAnimation {
      NumberAnimation { target: beam; property: "openH"; to: beam.height; duration: 230; easing.type: Easing.OutCubic }
      NumberAnimation { target: beam; property: "glow"; to: 0.32; duration: 230; easing.type: Easing.OutQuad }
    }
    // Brief overshoot/flicker as the tube settles.
    NumberAnimation { target: beam; property: "glow"; to: 0.1; duration: 40 }
    NumberAnimation { target: beam; property: "glow"; to: 0.2; duration: 30 }
    NumberAnimation { target: beam; property: "glow"; to: 0; duration: 90; easing.type: Easing.OutQuad }
    ScriptAction { script: beam.finished() }
  }

  SequentialAnimation {
    id: offAnim
    ParallelAnimation {
      NumberAnimation { target: beam; property: "openH"; to: 3; duration: 230; easing.type: Easing.InCubic }
      NumberAnimation { target: beam; property: "glow"; to: 0.95; duration: 230; easing.type: Easing.InQuad }
    }
    NumberAnimation { target: beam; property: "openW"; to: 6; duration: 130; easing.type: Easing.InQuad }
    ScriptAction { script: { beam.openW = 0; beam.openH = 0; beam.dotOpacity = 1 } }
    ParallelAnimation {
      NumberAnimation { target: beam; property: "dotSize"; to: 2; duration: 140; easing.type: Easing.InQuad }
      NumberAnimation { target: beam; property: "dotOpacity"; to: 0; duration: 140; easing.type: Easing.InQuad }
    }
    ScriptAction { script: beam.finished() }
  }
}
