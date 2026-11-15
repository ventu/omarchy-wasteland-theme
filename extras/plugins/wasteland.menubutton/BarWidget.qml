import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

// Omarchy's menu button (same clicks as omarchy.menu's bar widget: left opens
// the Omarchy menu, right opens a terminal). While the Wasteland theme's
// status strip is on (STATUS_STRIP in themes/wasteland/extras/features.conf,
// via wasteland-extras.json) it shows the radiation trefoil instead of the
// Omarchy logo. The menu itself is still omarchy.menu.
BarWidget {
  id: root
  moduleName: "wasteland.menubutton"

  property bool extrasStatusStrip: false
  readonly property string trefoilPath: Quickshell.env("HOME") + "/.config/omarchy/themes/wasteland/extras/assets/trefoil-accent.svg"

  function applyExtras(text) {
    try {
      root.extrasStatusStrip = JSON.parse(String(text || "{}")).statusStrip === true
    } catch (e) {
      root.extrasStatusStrip = false
    }
  }

  FileView {
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/wasteland-extras.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyExtras(text())
    onLoadFailed: root.applyExtras("")
  }

  Component {
    id: trefoilIcon
    // Fixed size: the icon loader has none of its own and scales the
    // painted bounds to the bar's icon size.
    Image {
      width: 16
      height: 16
      source: "file://" + root.trefoilPath
      sourceSize.width: 64
      sourceSize.height: 64
      fillMode: Image.PreserveAspectFit
      smooth: true
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.extrasStatusStrip ? "" : "\ue900"
    fontFamily: "omarchy"
    iconComponent: root.extrasStatusStrip ? trefoilIcon : null
    onPressed: function(button) {
      if (!root.bar) return
      if (button === Qt.RightButton) root.bar.run("xdg-terminal-exec")
      else root.bar.run("omarchy-shell shell toggle omarchy.menu '{\"menu\":\"root\"}'")
    }
  }
}
