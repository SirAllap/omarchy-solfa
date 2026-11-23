import QtQuick
import QtQuick.Window

// Offscreen scene host. After "--": output path; optional "gif" frames gapMs.
// Not for use on a visible desktop: run with QT_QPA_PLATFORM=offscreen.
Window {
  id: w
  default property alias content: stage.data
  property int cw: 460
  property int ch: 780
  property int pad: 36
  property int settleMs: 2400
  readonly property var args: Qt.application.arguments.indexOf("--") < 0 ? [] : Qt.application.arguments.slice(Qt.application.arguments.indexOf("--") + 1)
  readonly property bool grabbing: args.length > 0 && args[0] !== ""
  readonly property bool gif: args[1] === "gif"
  property int frames: Number(args[2]) || 60
  property int gap: Number(args[3]) || 0
  property int taken: 0
  property double started: 0
  width: cw + pad * 2
  height: ch + pad * 2
  visible: true
  color: "#07080b"

  Rectangle { anchors.fill: parent
    color: "#0a0b0d" }
  Glow { x: -width * 0.2; y: -height * 0.2; width: 600; height: 600; color: Theme.accent; strength: 0.14 }
  Glow { x: parent.width - width * 0.7; y: parent.height - height * 0.7; width: 640; height: 640; color: Theme.accent2; strength: 0.1 }
  // soft shadow under the panel
  Rectangle { x: w.pad - 2; y: w.pad + 14; width: w.cw + 4; height: w.ch; radius: 28; color: "#000"; opacity: 0.45 }
  Item { id: stage; x: w.pad; y: w.pad; width: w.cw; height: w.ch }

  function snap() {
    var n = taken++
    w.contentItem.grabToImage(function (r) {
      if (!gif) { r.saveToFile(args[0]); Qt.quit(); return }
      r.saveToFile(args[0] + "/f" + ("0000" + n).slice(-4) + ".png")
      if (taken >= frames) { console.log("ELAPSED " + (Date.now() - started)); Qt.quit() }
      else nextTimer.restart()
    })
  }
  Timer { id: nextTimer; interval: w.gap; onTriggered: w.snap() }
  Timer { interval: w.gif ? 250 : w.settleMs; running: w.grabbing; onTriggered: { w.started = Date.now(); w.snap() } }
}
