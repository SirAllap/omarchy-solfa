import QtQuick
import QtQuick.Window
import "../../lib" as Lib
import "../../lib/Pixel.js" as Pixel

// Renders the pill + join + card once, offscreen, and saves it. test_join.py mirrors the
// left half onto the right and compares. Args after `--`: output .ppm, pill left (logical,
// fractional), pill width (logical, fractional).
Window {
  id: win
  readonly property var args: Qt.application.arguments.slice(Qt.application.arguments.indexOf("--") + 1)
  readonly property real dpr: Screen.devicePixelRatio
  readonly property real pl: Number(args[1])
  readonly property real pw: Number(args[2])
  readonly property real left: Pixel.snap(pl, dpr)
  readonly property real wid: Pixel.snap(pw, dpr)
  readonly property real ph: 24
  readonly property real pTop: 6
  readonly property real pBottom: pTop + ph
  readonly property real cTop: pBottom + 3
  // The test mirrors the picture about the pill's centre line.
  width: 260
  height: 80
  visible: true
  color: "#dfb6c4"

  Rectangle { anchors.fill: parent; color: "#dfb6c4" }
  Rectangle {   // the card: a ring with the bridge's colours
    x: 0; y: win.cTop; width: win.width; height: 60
    color: "#f4f1ec"; border.width: 1; border.color: "#b9b4ae"
  }
  Rectangle {   // the pill
    x: win.left; y: win.pTop; width: win.wid; height: win.ph; radius: height / 2
    color: "#f4f1ec"; border.width: 1; border.color: "#b9b4ae"
  }
  Rectangle { x: win.left; y: win.pTop + 12; width: win.wid; height: 12; color: "#f4f1ec" }
  Lib.Bridge {
    dpr: win.dpr
    pillLeft: win.pl; pillWidth: win.pw
    pillTop: win.pTop; pillBottom: win.pBottom; cardTop: win.cTop
    fillColor: "#f4f1ec"; lineColor: "#b9b4ae"
  }

  Timer {
    interval: 600
    running: true
    onTriggered: win.contentItem.grabToImage(function (r) {
      r.saveToFile(win.args[0]); console.log("JOIN " + win.left + " " + win.wid + " " + win.dpr); Qt.quit() })
  }
}
