import QtQuick

// Four little bars that dance while a song plays (still when paused, or
// when the owner passes reduceMotion).
Row {
  id: e
  property bool playing: true
  property bool reduceMotion: false
  // False while the panel is closed: the bars must not tick in a hidden window.
  property bool panelOpen: true
  property color color: "white"
  spacing: 2
  height: 14
  Repeater {
    model: 4
    Rectangle {
      width: 3; radius: 1.5; color: e.color
      anchors.bottom: parent.bottom
      height: 4 + 0.5 * index
      SequentialAnimation on height {
        id: dance
        // Stopped (paused, closed): the bar goes back to its resting height, not frozen mid-beat.
        onRunningChanged: if (!running) parent.height = 4 + 0.5 * index
        running: e.playing && !e.reduceMotion && e.panelOpen; loops: Animation.Infinite
        NumberAnimation { to: 13 - index; duration: 280 + index * 90; easing.type: Easing.InOutSine }
        NumberAnimation { to: 4 + index; duration: 320 + index * 70; easing.type: Easing.InOutSine }
      }
    }
  }
}
