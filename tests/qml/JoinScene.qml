import QtQuick
import QtQuick.Window
import QtQuick.Shapes
import "../../lib" as Lib
import "../../lib/Pixel.js" as Pixel

// Renders the pill + join + card once, offscreen, and saves it. test_join.py mirrors the
// left half onto the right and compares. Args after `--`: output .ppm, pill left (logical,
// fractional), pill width (logical, fractional), mode: "line" (default), "plain" (no outlines,
// so the fill edge alone can be measured) or "aliased" (plain, with the geometry renderer).
Window {
  id: win
  readonly property var args: Qt.application.arguments.slice(Qt.application.arguments.indexOf("--") + 1)
  readonly property string mode: args[3] || "line"
  readonly property bool lined: mode === "line"
  readonly property real dpr: Screen.devicePixelRatio
  readonly property real pl: Number(args[1])
  readonly property real pw: Number(args[2])
  // "legacy" = how ef99967 placed things: the join on whole logical px, the pill where it falls.
  readonly property bool legacy: mode === "legacy"
  readonly property real left: legacy ? pl : Pixel.snap(pl, dpr)
  readonly property real wid: legacy ? pw : Pixel.snap(pw, dpr)
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
    color: "#f4f1ec"; border.width: win.lined ? 1 : 0; border.color: "#b9b4ae"
  }
  Rectangle {   // the pill
    x: win.left; y: win.pTop; width: win.wid; height: win.ph; radius: height / 2
    color: "#f4f1ec"; border.width: win.lined ? 1 : 0; border.color: "#b9b4ae"
  }
  Rectangle { x: win.left; y: win.pTop + 12; width: win.wid; height: 12; color: "#f4f1ec" }
  Lib.Bridge {
    dpr: win.legacy ? 1 : win.dpr
    pillLeft: win.pl; pillWidth: win.pw
    pillTop: win.pTop; pillBottom: win.pBottom; cardTop: win.cTop
    fillColor: "#f4f1ec"; lineColor: win.lined ? "#b9b4ae" : "transparent"
    rendererType: win.mode === "aliased" ? Shape.GeometryRenderer : Shape.CurveRenderer
  }

  Timer {
    interval: 600
    running: true
    onTriggered: win.contentItem.grabToImage(function (r) {
      r.saveToFile(win.args[0]); console.log("JOIN " + win.left + " " + win.wid + " " + win.dpr); Qt.quit() })
  }
}
