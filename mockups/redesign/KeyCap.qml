import QtQuick

// A key and what it does, for the hint line.
Row {
  id: k
  property string keys: ""
  property string label: ""
  spacing: 6
  Rectangle {
    height: 20; width: Math.max(20, kt.width + 10); radius: 6
    color: Theme.wash; border.width: 1; border.color: Theme.hair
    anchors.verticalCenter: parent.verticalCenter
    Text { id: kt; anchors.centerIn: parent; text: k.keys; color: Theme.dim; font.family: "monospace"; font.pixelSize: 11 }
  }
  Text { text: k.label; anchors.verticalCenter: parent.verticalCenter; color: Theme.faint; font.family: Theme.font; font.pixelSize: 11 }
}
