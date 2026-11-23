import QtQuick

// The Solfa logo, version C: a dark vinyl record with fine grooves, a
// centred label and hole, and a thin rim. Drawn here as a stand-in; the
// final source lives in the logo worker's folder.
Item {
  id: l
  property real size: 28
  width: size; height: size
  readonly property real k: size / 100
  Rectangle { anchors.centerIn: parent; width: 92 * l.k; height: width; radius: width / 2; color: "#1d1f24"
    border.width: Math.max(1, 2 * l.k); border.color: Qt.rgba(0.9, 0.91, 0.93, 0.8) }
  Repeater { model: [40, 36, 32, 28, 24]
    Rectangle { visible: l.size >= 40; anchors.centerIn: parent; width: modelData * 2 * l.k; height: width; radius: width / 2; color: "transparent"
      border.width: 1; border.color: Qt.rgba(0.9, 0.91, 0.93, 0.18) } }
  Rectangle { anchors.centerIn: parent; width: 30 * l.k; height: width; radius: width / 2; color: Theme.accent }
  Rectangle { anchors.centerIn: parent; width: Math.max(2, 7 * l.k); height: width; radius: width / 2; color: "#121316" }
}
