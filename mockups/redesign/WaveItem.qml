import QtQuick

// Enters in a priority wave: high at 0 ms, medium at 150 ms, low at 300 ms.
Item {
  id: w
  property int priority: 0
  property bool go: true
  property bool arrived: false
  default property alias content: box.data
  opacity: arrived ? 1 : 0
  Behavior on opacity { enabled: !Motion.reduce; NumberAnimation { duration: 360; easing.type: Easing.OutCubic } }
  onGoChanged: if (!go) arrived = false
  Timer { interval: Motion.wave(w.priority); running: w.go; onTriggered: w.arrived = true }
  Item { id: box; width: w.width; height: w.height
    transform: Translate { y: w.arrived ? 0 : 16; Behavior on y { enabled: !Motion.reduce; NumberAnimation { duration: 480; easing.type: Easing.OutQuint } } } }
}
