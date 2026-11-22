import QtQuick

// One tile of the motion lab: a title, a live demo, and one line of what it is.
Item {
  id: t
  property string title: ""
  property string note: ""
  default property alias demo: stage.data
  width: 300; height: 250
  Rectangle { anchors.fill: parent; radius: 22; color: Theme.surface; border.width: 1; border.color: Theme.hair }
  Text { x: 18; y: 14; text: t.title; color: Theme.fg; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.Bold }
  Item { id: stage; x: 0; y: 40; width: parent.width; height: 150; clip: true }
  Text { x: 18; y: 196; width: parent.width - 36; text: t.note; wrapMode: Text.WordWrap; color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 }
}
