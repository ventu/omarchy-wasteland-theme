import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons

Item {
  id: root

  property string backgroundPath: ""
  property string videoPosterPath: ""
  property int backgroundVersion: 0
  property bool fingerprintConfigured: false
  property bool fingerprintUnavailable: false
  property bool authenticatingPassword: false
  property string failureMessage: ""
  property int failedAttempts: 0
  property bool inputEnabled: true
  property bool loadBackground: true
  property string passwordText: ""
  property bool syncingPasswordText: false
  readonly property string accountName: Quickshell.env("USER") || Quickshell.env("LOGNAME") || ""

  readonly property string placeholderText: "ENTER PASSWORD"
  readonly property real ui: Math.max(1, Math.min((width > 0 ? width : 1280) / 1280, (height > 0 ? height : 800) / 800))
  readonly property int fieldWidth: Math.round(300 * ui)
  readonly property int fieldHeight: Math.round(32 * ui)
  readonly property int fieldFontSize: Math.round(14 * ui)
  readonly property int passwordDotFontSize: Math.round(15 * ui)
  readonly property int passwordDotLetterSpacing: Math.round(3 * ui)
  readonly property real fingerprintReserve: fingerprintConfigured ? Math.round(fingerprintIcon.implicitWidth + 12) : 0
  readonly property real passwordDotScale: dotMetrics.advanceWidth > 0
    ? Math.min(1, (passwordInput.width - 4) / dotMetrics.advanceWidth)
    : 1
  readonly property bool showPasswordCursor: !authenticatingPassword && failureMessage.length === 0
  readonly property bool errorState: failureMessage.length > 0

  readonly property string monoFont: "JetBrainsMono Nerd Font"
  readonly property color colorBg: "#0b0e09"
  readonly property color colorBgLift: "#14170f"
  readonly property color colorFg: "#a8b59a"
  readonly property color colorBright: "#d4dcc8"
  readonly property color colorPhosphor: "#8fbf6a"
  readonly property color colorAccent: "#7f9a6a"
  readonly property color colorMuted: "#6a7460"
  readonly property color colorRule: "#3a4232"
  readonly property color colorFrame: "#2a3123"
  readonly property color colorDenied: "#a85046"
  readonly property var tabLabels: ["STAT", "INV", "DATA", "MAP", "RADIO"]
  readonly property string activeTab: "STAT"

  property string clockText: formatClock()
  property bool caretOn: true
  property string batteryCapacity: ""
  property string batteryStatus: ""
  property string hostNameText: "OMARCHY"

  readonly property string powerText: {
    if (!batteryCapacity) return ""
    var st = String(batteryStatus || "").toUpperCase()
    var suffix = st === "CHARGING" ? " +" : (st === "DISCHARGING" ? " -" : "")
    return "PWR  " + batteryCapacity + "%" + suffix
  }
  readonly property string wallpaperSource: {
    var p = root.videoPosterPath || root.backgroundPath
    if (!p || p.length === 0) return ""
    var url = (p.indexOf("file:") === 0 || p.indexOf("http") === 0) ? p : ("file://" + p)
    return url + (root.backgroundVersion ? ("?v=" + root.backgroundVersion) : "")
  }

  signal submitPassword(string password)
  signal passwordTextEdited(string password)
  signal clearFailureRequested()
  signal wakeRequested()

  function formatClock() {
    return Qt.formatDateTime(new Date(), "yyyy-MM-dd  HH:mm")
  }

  function forcePasswordFocus() {
    passwordInput.forceActiveFocus()
  }

  function clearPassword() {
    passwordTextEdited("")
  }

  function submitCurrentPassword() {
    if (!inputEnabled || authenticatingPassword) return
    var submitted = passwordText
    passwordTextEdited("")
    if (submitted.length > 0) submitPassword(submitted)
  }

  function dropsAutoRepeat(key) {
    return key !== Qt.Key_Backspace && key !== Qt.Key_Delete
  }

  function syncPasswordText() {
    if (passwordInput.text === passwordText) return
    syncingPasswordText = true
    passwordInput.text = passwordText
    syncingPasswordText = false
  }

  function restorePasswordFocus() {
    if (inputEnabled && passwordInput.enabled && !passwordInput.activeFocus) forcePasswordFocus()
  }

  onPasswordTextChanged: syncPasswordText()
  onInputEnabledChanged: {
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
  }

  Window.onActiveFocusItemChanged: Qt.callLater(restorePasswordFocus)
  Component.onCompleted: {
    syncPasswordText()
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
  }

  FileView {
    id: hostFile
    path: "/etc/hostname"
    blockLoading: true
    printErrors: false
    onLoaded: root.hostNameText = String(text() || "").trim().toUpperCase() || "OMARCHY"
  }

  FileView {
    id: batteryFile
    path: "/sys/class/power_supply/BAT0/capacity"
    watchChanges: true
    blockLoading: true
    printErrors: false
    onLoaded: root.batteryCapacity = String(text() || "").trim()
    onFileChanged: reload()
  }

  FileView {
    id: batteryStatusFile
    path: "/sys/class/power_supply/BAT0/status"
    watchChanges: true
    blockLoading: true
    printErrors: false
    onLoaded: root.batteryStatus = String(text() || "").trim()
    onFileChanged: reload()
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: root.clockText = root.formatClock()
  }

  Timer {
    interval: 530
    running: root.showPasswordCursor
    repeat: true
    onTriggered: root.caretOn = !root.caretOn
    onRunningChanged: if (running) root.caretOn = true
  }

  TextMetrics {
    id: dotMetrics
    font.family: root.monoFont
    font.pixelSize: root.passwordDotFontSize
    font.letterSpacing: root.passwordDotLetterSpacing
    text: "●".repeat(passwordInput.text.length)
  }

  TextMetrics {
    id: placeholderMetrics
    font.family: root.monoFont
    font.pixelSize: root.fieldFontSize
    font.letterSpacing: 1
    text: root.placeholderText
  }

  Rectangle {
    anchors.fill: parent
    color: root.colorBg
  }

  Image {
    anchors.fill: parent
    visible: root.loadBackground && root.wallpaperSource.length > 0
    source: root.wallpaperSource
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    cache: true
    smooth: true
  }

  Rectangle {
    anchors.fill: parent
    color: root.colorBg
    opacity: root.loadBackground && root.wallpaperSource.length > 0 ? 0.84 : 1
  }

  Canvas {
    id: vignette
    anchors.fill: parent
    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      var cx = width * 0.5
      var cy = height * 0.48
      var r = Math.max(width, height) * 0.72
      var g = ctx.createRadialGradient(cx, cy, Math.min(width, height) * 0.18, cx, cy, r)
      g.addColorStop(0.0, "rgba(11, 14, 9, 0)")
      g.addColorStop(0.7, "rgba(11, 14, 9, 0.28)")
      g.addColorStop(1.0, "rgba(0, 0, 0, 0.62)")
      ctx.fillStyle = g
      ctx.fillRect(0, 0, width, height)
    }
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
  }

  Image {
    anchors.fill: parent
    source: Qt.resolvedUrl("scanlines.png")
    fillMode: Image.Tile
    smooth: false
    asynchronous: true
    cache: true
    opacity: 0.22
  }

  Rectangle {
    anchors.fill: parent
    anchors.margins: Math.round(10 * root.ui)
    color: "transparent"
    border.width: 1
    border.color: root.colorFrame
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    onClicked: { root.wakeRequested(); root.forcePasswordFocus() }
    onPositionChanged: root.wakeRequested()
  }

  // Header
  Item {
    id: header
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.leftMargin: Math.round(28 * root.ui)
    anchors.rightMargin: Math.round(28 * root.ui)
    height: Math.round(parent.height * 0.078)

    Text {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: "WASTELAND TERMINAL  V1.0"
      color: root.colorPhosphor
      font.family: root.monoFont
      font.pixelSize: Math.round(15 * root.ui)
      font.letterSpacing: 1
    }

    Text {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.clockText
      color: root.colorFg
      font.family: root.monoFont
      font.pixelSize: Math.round(15 * root.ui)
      font.letterSpacing: 1
    }

    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: 1
      color: root.colorAccent
      opacity: 0.7
    }
  }

  // Decorative wrist-terminal tabs
  Row {
    id: tabRow
    anchors.top: header.bottom
    anchors.topMargin: Math.round(14 * root.ui)
    anchors.horizontalCenter: parent.horizontalCenter
    spacing: Math.round(28 * root.ui)

    Repeater {
      model: root.tabLabels
      delegate: Item {
        width: tabLabel.implicitWidth + Math.round(16 * root.ui)
        height: tabLabel.implicitHeight + Math.round(10 * root.ui)

        Text {
          id: tabLabel
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: parent.top
          textFormat: Text.PlainText
          text: modelData
          color: modelData === root.activeTab ? root.colorPhosphor : root.colorMuted
          font.family: root.monoFont
          font.pixelSize: Math.round(14 * root.ui)
          font.letterSpacing: 2
          font.bold: modelData === root.activeTab
        }

        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: Math.max(1, Math.round(2 * root.ui))
          color: root.colorPhosphor
          visible: modelData === root.activeTab
          opacity: 0.85
        }
      }
    }
  }

  // Center stack
  Column {
    id: centerColumn
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: Math.round(8 * root.ui)
    spacing: Math.round(14 * root.ui)

    Image {
      anchors.horizontalCenter: parent.horizontalCenter
      source: Qt.resolvedUrl("terminal-emblem.svg")
      height: Math.round(150 * root.ui)
      width: Math.round(height * 240 / 200)
      sourceSize.width: width * 2
      sourceSize.height: height * 2
      smooth: true
      mipmap: true
      asynchronous: true
      cache: true
      fillMode: Image.PreserveAspectFit
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.PlainText
      text: "TERMINAL LOCKED"
      color: root.colorPhosphor
      font.family: root.monoFont
      font.pixelSize: Math.round(22 * root.ui)
      font.letterSpacing: 4
      font.bold: true
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.PlainText
      text: root.accountName
      color: root.colorFg
      font.family: root.monoFont
      font.pixelSize: Math.round(16 * root.ui)
      font.letterSpacing: 1
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.PlainText
      visible: root.authenticatingPassword || root.errorState
      text: root.authenticatingPassword ? "VERIFYING..." : "ACCESS DENIED"
      color: root.authenticatingPassword ? root.colorPhosphor : root.colorDenied
      font.family: root.monoFont
      font.pixelSize: Math.round(14 * root.ui)
      font.letterSpacing: 2
      font.bold: true
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.PlainText
      visible: root.errorState && root.failedAttempts > 0 && !root.authenticatingPassword
      text: "ATTEMPT  " + root.failedAttempts
      color: root.colorMuted
      font.family: root.monoFont
      font.pixelSize: Math.round(11 * root.ui)
      font.letterSpacing: 1
    }

    Item { width: 1; height: Math.round(6 * root.ui) }

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Math.round(10 * root.ui)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: ">"
        color: root.colorPhosphor
        font.family: root.monoFont
        font.pixelSize: Math.round(18 * root.ui)
        font.bold: true
      }

      Rectangle {
        id: inputField
        width: root.fieldWidth
        height: root.fieldHeight
        color: root.colorBgLift
        border.width: 1
        border.color: root.errorState ? root.colorDenied : root.colorAccent
        clip: true

        TextInput {
          id: passwordInput
          anchors.fill: parent
          anchors.topMargin: 2
          anchors.bottomMargin: 2
          anchors.rightMargin: 10 + root.fingerprintReserve
          anchors.leftMargin: 12
          verticalAlignment: TextInput.AlignVCenter
          horizontalAlignment: TextInput.AlignLeft
          activeFocusOnPress: true
          clip: true
          enabled: root.inputEnabled && !root.authenticatingPassword
          readOnly: root.authenticatingPassword
          echoMode: TextInput.Password
          passwordCharacter: "\u25CF"
          passwordMaskDelay: 0
          color: root.colorPhosphor
          selectionColor: "#2a3123"
          selectedTextColor: root.colorPhosphor
          font.family: root.monoFont
          font.pixelSize: text.length > 0 ? Math.max(1, Math.floor(root.passwordDotFontSize * root.passwordDotScale)) : root.fieldFontSize
          font.letterSpacing: text.length > 0 ? root.passwordDotLetterSpacing * root.passwordDotScale : 0
          cursorVisible: activeFocus && root.inputEnabled && root.showPasswordCursor && text.length > 0
          cursorDelegate: Item {
            width: Math.round(10 * root.ui)
            Rectangle {
              width: Math.round(8 * root.ui)
              height: Math.max(2, Math.round(2 * root.ui))
              anchors.left: parent.left
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Math.round(6 * root.ui)
              color: root.colorPhosphor
              visible: root.caretOn && root.showPasswordCursor
            }
          }

          onTextChanged: {
            if (!root.syncingPasswordText) root.passwordTextEdited(text)
            if (text.length > 0) root.wakeRequested()
            if (text.length > 0 && root.failureMessage.length > 0) root.clearFailureRequested()
          }

          onAccepted: root.submitCurrentPassword()

          Keys.onPressed: function(event) {
            root.wakeRequested()
            if (event.isAutoRepeat && root.dropsAutoRepeat(event.key)) {
              event.accepted = true
              return
            }
            if (event.key === Qt.Key_Escape || (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_U)) {
              root.passwordTextEdited("")
              event.accepted = true
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          anchors.left: passwordInput.left
          anchors.right: passwordInput.right
          anchors.top: passwordInput.top
          anchors.bottom: passwordInput.bottom
          text: root.placeholderText
          visible: passwordInput.text.length === 0 && !root.authenticatingPassword && !root.errorState
          color: root.colorMuted
          font.family: root.monoFont
          font.pixelSize: root.fieldFontSize
          font.letterSpacing: 1
          horizontalAlignment: Text.AlignLeft
          verticalAlignment: Text.AlignVCenter
          elide: Text.ElideRight
        }

        // Blinking caret when the field is empty (preview and idle lock)
        Text {
          visible: passwordInput.text.length === 0 && root.showPasswordCursor && root.caretOn && !root.authenticatingPassword && !root.errorState
          anchors.left: passwordInput.left
          anchors.leftMargin: placeholderMetrics.advanceWidth + Math.round(2 * root.ui)
          anchors.verticalCenter: passwordInput.verticalCenter
          textFormat: Text.PlainText
          text: "_"
          color: root.colorPhosphor
          font.family: root.monoFont
          font.pixelSize: root.fieldFontSize
        }

        Text {
          id: fingerprintIcon
          objectName: "fingerprintIndicator"
          textFormat: Text.PlainText
          anchors.right: parent.right
          anchors.rightMargin: 10
          anchors.verticalCenter: parent.verticalCenter
          visible: root.fingerprintConfigured
          text: root.fingerprintUnavailable ? "󰺱" : "󰈷"
          color: root.fingerprintUnavailable ? root.colorDenied : root.colorMuted
          font.family: root.monoFont
          font.pixelSize: Math.round(root.fieldFontSize * 1.1)
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
        }
      }

      Rectangle {
        width: Math.round(58 * root.ui)
        height: inputField.height
        color: root.colorBgLift
        border.width: 1
        border.color: root.colorAccent
        opacity: root.inputEnabled && !root.authenticatingPassword ? 1 : 0.45

        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: "ENT"
          color: root.colorPhosphor
          font.family: root.monoFont
          font.pixelSize: Math.round(12 * root.ui)
          font.letterSpacing: 1
          font.bold: true
        }

        MouseArea {
          anchors.fill: parent
          enabled: root.inputEnabled && !root.authenticatingPassword
          onClicked: root.submitCurrentPassword()
        }
      }
    }

    Text {
      objectName: "fingerprintUnavailableNotice"
      textFormat: Text.PlainText
      anchors.horizontalCenter: parent.horizontalCenter
      visible: root.fingerprintConfigured && root.fingerprintUnavailable
      text: "FINGERPRINT READER OFFLINE"
      color: root.colorMuted
      font.family: root.monoFont
      font.pixelSize: Math.round(11 * root.ui)
      font.letterSpacing: 1
    }

    Item { width: 1; height: Math.round(10 * root.ui) }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.PlainText
      text: "HP  100/100      AP  90/90      RAD  0"
      color: root.colorMuted
      font.family: root.monoFont
      font.pixelSize: Math.round(13 * root.ui)
      font.letterSpacing: 1
    }
  }

  // Footer
  Item {
    id: footer
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.leftMargin: Math.round(28 * root.ui)
    anchors.rightMargin: Math.round(28 * root.ui)
    height: Math.round(parent.height * 0.078)

    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: 1
      color: root.colorAccent
      opacity: 0.7
    }

    Text {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: "PERSONAL INTERFACE OS"
      color: root.colorMuted
      font.family: root.monoFont
      font.pixelSize: Math.round(12 * root.ui)
      font.letterSpacing: 1
    }

    Text {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: "UNIT  " + root.hostNameText + (root.powerText.length ? ("      " + root.powerText) : "")
      color: root.colorFg
      font.family: root.monoFont
      font.pixelSize: Math.round(12 * root.ui)
      font.letterSpacing: 1
    }
  }
}
