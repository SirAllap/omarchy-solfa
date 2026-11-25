import QtQuick
import "../lib"
import qs.Ui
import qs.Commons

// Loading state on a cover: a soft band of light sweeps across it, the way modern players show a
// card on its way. Reduce motion: the band stays still.
Item {
  id: root
  property real radius: 0
  property bool running: visible
  anchors.fill: parent
  Item {
    id: band
    anchors.fill: parent
    clip: true
    Rectangle {
      id: light
      width: root.width * 0.9
      height: root.height * 2.2
      y: -root.height * 0.6
      rotation: 20
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0) }
        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.22) }
        GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
      }
      NumberAnimation on x {
        running: root.running && !Style.reduceMotion
        from: -light.width * 1.2
        to: root.width + light.width * 0.2
        duration: 1400
        easing.type: Easing.InOutQuad
        loops: Animation.Infinite
      }
    }
  }
}
