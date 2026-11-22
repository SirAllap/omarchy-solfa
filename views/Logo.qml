import QtQuick
import qs.Commons

// Solfa's logo: a dark vinyl record with fine grooves, a centred label and
// hole, and a thin rim (version C). The label takes the theme's accent.
// Every ring is a Rectangle on whole pixels, so all of them share one centre:
// the box is made even, each ring is made even, and x/y are integers.
Item {
  id: root
  property real size: 20
  property color rim: Color.foreground
  property color label: Color.accent
  property color disc: "#1d1f24"
  readonly property int box: 2 * Math.round(size / 2)
  implicitWidth: box
  implicitHeight: box
  readonly property real k: box / 100
  // Even whole-pixel diameter for a ring that is pct percent of the box.
  function d(pct) { return Math.max(2, 2 * Math.round(pct * k / 2)) }

  Rectangle {
    x: (root.box - width) / 2; y: x
    width: root.d(92); height: width; radius: width / 2
    color: root.disc
    border.width: Math.max(1, Math.round(2 * root.k))
    border.color: Qt.rgba(root.rim.r, root.rim.g, root.rim.b, 0.8)
  }
  Repeater {
    model: [40, 36, 32, 28, 24]
    Rectangle {
      required property int modelData
      visible: root.box >= 40
      x: (root.box - width) / 2; y: x
      width: root.d(modelData * 2); height: width; radius: width / 2
      color: "transparent"
      border.width: 1
      border.color: Qt.rgba(root.rim.r, root.rim.g, root.rim.b, 0.18)
    }
  }
  Rectangle { x: (root.box - width) / 2; y: x; width: root.d(30); height: width; radius: width / 2; color: root.label }
  Rectangle { x: (root.box - width) / 2; y: x; width: root.d(7); height: width; radius: width / 2; color: "#121316" }
}
