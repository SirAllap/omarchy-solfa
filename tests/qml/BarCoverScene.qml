import QtQuick
import QtQuick.Window
import "../../views" as Views

// Renders the bar cover once, offscreen, and saves it: a red cover in a
// green ring, placed at a bar-like offset. test_render.py measures it.
// Arguments after `--`: bar size, output file, picture, "dim" for a paused
// song.
Window {
  id: win
  readonly property var args: Qt.application.arguments.slice(Qt.application.arguments.indexOf("--") + 1)
  readonly property int barSize: Number(args[0]) || 26
  width: barSize * 2
  height: barSize
  visible: true
  color: "black"

  Views.BarCover {
    id: cover
    x: Math.round(win.barSize * 0.3)
    anchors.verticalCenter: parent.verticalCenter
    barSize: win.barSize
    hasTrack: true
    dim: win.args[3] === "dim"
    progress: 1
    ringColor: "#00ff00"
    trackColor: "#00ff00"
    source: Qt.resolvedUrl(win.args[2] || "red.png")
  }

  Timer {
    interval: 500
    running: true
    onTriggered: win.contentItem.grabToImage(function (r) { r.saveToFile(win.args[1]); Qt.quit() })
  }
}
