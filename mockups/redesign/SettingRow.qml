import QtQuick

// A label (and a line of help) on the left, its control on the right.
Item {
  id: r
  property string label: ""
  property string help: ""
  property bool danger: false
  default property alias control: slot.data
  z: slot.children.length > 0 && slot.children[0].z > 0 ? 50 : 0
  width: parent ? parent.width : 340
  height: help !== "" ? 58 : 50
  Column { anchors.verticalCenter: parent.verticalCenter; width: parent.width - slot.width - 14; spacing: 2
    Text { width: parent.width; text: r.label; wrapMode: Text.WordWrap; color: r.danger ? Theme.err : Theme.fg; font.family: Theme.font; font.pixelSize: 14 }
    Text { visible: r.help !== ""; width: parent.width; text: r.help; color: Theme.faint; font.family: Theme.font; font.pixelSize: 11; wrapMode: Text.WordWrap } }
  Item { id: slot; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: childrenRect.width; height: childrenRect.height }
  Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.hair }
}
