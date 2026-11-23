import QtQuick

// Four little bars that dance while a song plays.
Row {
  id: e
  property bool playing: true
  property color color: Theme.accent
  spacing: 2
  height: 14
  Repeater {
    model: 4
    Rectangle {
      width: 3; radius: 1.5; color: e.color
      anchors.bottom: parent.bottom
      height: 4 + 0.5 * index
      SequentialAnimation on height {
        running: e.playing && Motion.live; loops: Animation.Infinite
        NumberAnimation { to: 13 - index; duration: 280 + index * 90; easing.type: Easing.InOutSine }
        NumberAnimation { to: 4 + index; duration: 320 + index * 70; easing.type: Easing.InOutSine }
      }
    }
  }
}
