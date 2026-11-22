import QtQuick
import qs.Commons

// Solfa's logo: a dark vinyl record with fine grooves, a centred label and
// hole, and a thin rim (version C). The label takes the theme's accent.
Item {
  id: root
  property real size: 20
  property color rim: Color.foreground
  property color label: Color.accent
  implicitWidth: size
  implicitHeight: size
  readonly property real k: size / 100

  Rectangle {
    anchors.centerIn: parent
    width: 92 * root.k; height: width; radius: width / 2
    color: "#1d1f24"
    border.width: Math.max(1, 2 * root.k)
    border.color: Qt.rgba(root.rim.r, root.rim.g, root.rim.b, 0.8)
  }
  Repeater {
    model: [40, 36, 32, 28, 24]
    Rectangle {
      required property int modelData
      visible: root.size >= 40
      anchors.centerIn: parent
      width: modelData * 2 * root.k; height: width; radius: width / 2
      color: "transparent"
      border.width: 1
      border.color: Qt.rgba(root.rim.r, root.rim.g, root.rim.b, 0.18)
    }
  }
  Rectangle { anchors.centerIn: parent; width: 30 * root.k; height: width; radius: width / 2; color: root.label }
  Rectangle { anchors.centerIn: parent; width: Math.max(2, 7 * root.k); height: width; radius: width / 2; color: "#121316" }
}
