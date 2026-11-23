import QtQuick

// A square cover with a name, for playlists, albums and artists.
Item {
  id: g
  property int index: 0
  property var item: ({ t: "", n: "", seed: 0 })
  property bool round: false
  property bool hot: false
  property bool go: true
  property bool entered: false
  onGoChanged: if (!go) entered = false
  Timer { interval: Motion.wave(1) + g.index * 60; running: g.go; onTriggered: g.entered = true }
  opacity: entered ? 1 : 0
  Behavior on opacity { enabled: !Motion.reduce; NumberAnimation { duration: 340 } }
  property real pop: entered ? 1 : 0.86
  Behavior on pop { enabled: !Motion.reduce; SpringAnimation { spring: 4; damping: 0.4; epsilon: 0.002 } }
  scale: pop
  property real lift: (hot || ma.containsMouse) ? 1.04 : 1
  Behavior on lift { enabled: !Motion.reduce; SpringAnimation { spring: 6; damping: 0.45; epsilon: 0.001 } }
  Item { id: inner; anchors.fill: parent; scale: g.lift
    Cover { id: cv; x: g.round ? (parent.width - width) / 2 : 0; width: g.round ? Math.min(parent.width, parent.height - 38) : parent.width; height: g.round ? width : parent.width; seed: g.item.seed; radius: 16; round: g.round; lit: g.hot
      Rectangle { visible: g.hot; anchors.fill: parent; radius: g.round ? width / 2 : 16; color: Qt.rgba(0, 0, 0, 0.35)
        IconButton { anchors.centerIn: parent; icon: "play"; size: 40; glyph: 18; primary: true } } }
    Text { y: cv.height + 6; width: parent.width; horizontalAlignment: g.round ? Text.AlignHCenter : Text.AlignLeft; text: g.item.t; elide: Text.ElideRight; color: Theme.fg; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
    Text { y: cv.height + 23; width: parent.width; horizontalAlignment: g.round ? Text.AlignHCenter : Text.AlignLeft; text: g.item.n; elide: Text.ElideRight; color: Theme.faint; font.family: Theme.font; font.pixelSize: 11 }
  }
  MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
}
