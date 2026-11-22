import QtQuick
import QtQuick.Window

// The gallery. Run it on its own, no engine, fake data:
//   qml mockups/redesign/Gallery.qml            (Qt's own tool, opens a window)
//   quickshell -p mockups/redesign/shell.qml    (the same, as a Quickshell config)
// With "-- out.png" after the file it renders once and quits (offscreen use).
Window {
  id: w
  readonly property var args: Qt.application.arguments.indexOf("--") < 0 ? [] : Qt.application.arguments.slice(Qt.application.arguments.indexOf("--") + 1)
  readonly property bool grabbing: args.length > 0 && args[0] !== ""
  readonly property int pad: 36
  width: grabbing ? body.width + 2 * pad : Math.min(body.width + 2 * pad, 1500)
  height: grabbing ? body.height + 2 * pad : Math.min(body.height + 2 * pad, 940)
  visible: true
  title: "Solfa redesign: gallery"
  color: "#07080b"
  Rectangle { anchors.fill: parent; color: "#0a0b0d" }
  Flickable {
    anchors.fill: parent; contentWidth: body.width + 2 * w.pad; contentHeight: body.height + 2 * w.pad; clip: true; boundsBehavior: Flickable.StopAtBounds
    Gallery_Body { id: body; x: w.pad; y: w.pad }
  }
  Timer { interval: 5200; running: w.grabbing; onTriggered: w.contentItem.grabToImage(function (r) { r.saveToFile(w.args[0]); Qt.quit() }) }
}
