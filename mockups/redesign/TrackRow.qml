import QtQuick

// A song row. It slides in from the right with a short delay per index.
Item {
  id: r
  property int index: 0
  property var track: ({ t: "", a: "", d: "", seed: 0 })
  property bool current: false
  property bool playing: true
  property bool hot: false
  property bool selected: false
  property bool removable: false
  property string meta: ""
  property bool go: true
  property bool entered: false
  onGoChanged: if (!go) entered = false
  property real slide: entered ? 0 : 34
  height: 58
  width: parent ? parent.width : 420
  opacity: entered ? 1 : 0
  Behavior on opacity { enabled: !Motion.reduce; NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
  Behavior on slide { enabled: !Motion.reduce; NumberAnimation { duration: 460; easing.type: Easing.OutQuint } }
  transform: Translate { x: r.slide }
  Timer { interval: Motion.wave(1) + r.index * 50; running: r.go; onTriggered: r.entered = true }

  Rectangle {
    anchors.fill: parent; anchors.topMargin: 2; anchors.bottomMargin: 2; radius: 14
    color: r.current ? Theme.a(Theme.accent, 0.13) : (r.hot ? Theme.wash : "transparent")
    border.width: r.selected ? 1 : 0; border.color: Theme.a(Theme.accent, 0.7)
    Behavior on color { enabled: !Motion.reduce; ColorAnimation { duration: 140 } }
    Rectangle { visible: r.current; x: 0; anchors.verticalCenter: parent.verticalCenter; width: 3; height: 24; radius: 1.5; color: Theme.accent }
  }
  Item {
    id: thumb; x: 12; anchors.verticalCenter: parent.verticalCenter; width: 42; height: 42
    Cover { anchors.fill: parent; radius: 10; seed: r.track.seed; breathe: r.current; playing: r.playing }
    Rectangle { visible: r.current; anchors.fill: parent; radius: 10; color: Qt.rgba(0, 0, 0, 0.45)
      Equalizer { anchors.centerIn: parent; playing: r.playing; color: "#fff" } }
  }
  Column {
    anchors.verticalCenter: parent.verticalCenter
    x: 66; width: parent.width - 66 - 110
    spacing: 2
    Text { width: parent.width; text: r.track.t; elide: Text.ElideRight; color: r.current ? Theme.accent : Theme.fg; font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold }
    Text { width: parent.width; text: r.meta !== "" ? r.meta : r.track.a; elide: Text.ElideRight; color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 }
  }
  Text { anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter; text: r.track.d; color: Theme.faint; font.family: Theme.font; font.pixelSize: 12; opacity: r.hot ? 0 : 1; Behavior on opacity { enabled: !Motion.reduce; NumberAnimation { duration: 120 } } }
  Row {
    anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; spacing: 0
    opacity: r.hot ? 1 : 0
    Behavior on opacity { enabled: !Motion.reduce; NumberAnimation { duration: 140 } }
    IconButton { icon: r.removable ? "close" : "next2"; size: 32; glyph: 15; tip: r.removable ? "Remove (x)" : "Play next (e)" }
    IconButton { icon: "plus"; size: 32; glyph: 15 }
    IconButton { icon: "radio"; size: 32; glyph: 15 }
  }
  MouseArea { anchors.fill: parent; hoverEnabled: true; onEntered: r.hot = true; onExited: r.hot = false; acceptedButtons: Qt.NoButton }
}
