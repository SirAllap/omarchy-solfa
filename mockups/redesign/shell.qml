import Quickshell
import QtQuick

// Opens the gallery as a Quickshell config:  quickshell -p mockups/redesign/shell.qml
// Fake data only. It never talks to Solfa's engine or the live panel.
ShellRoot {
  FloatingWindow {
    title: "Solfa redesign: gallery"
    implicitWidth: 1500
    implicitHeight: 940
    color: "#07080b"
    Flickable {
      anchors.fill: parent; contentWidth: body.width + 72; contentHeight: body.height + 72; clip: true
      Gallery_Body { id: body; x: 36; y: 36 }
    }
  }
}
